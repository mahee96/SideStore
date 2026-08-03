//
//  VerifyCertificateOperation.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import CoreData
import Security
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class VerifyCertificateOperation: BasePipelineOperation<AppOperationContext, Void>, @unchecked Sendable {

    private enum CertificateValidationResult {
        case valid(isCrossSigned: Bool)
        case revoked
    }
    
    override func execute(parentProgress: Progress?) async throws {
        debugLog("[VerifyCertificateOperation] execute() started")
        defer { debugLog("[VerifyCertificateOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        guard let team = self.context.authenticatedContext.team, let session = self.context.authenticatedContext.session else {
            debugLog("[VerifyCertificateOperation] Skipping certificate verification: team or session missing in context.")
            self.setProgress(100)
            return
        }
        
        // 1. Obtain active portal certificates (auth context or direct fetch as fallback)
        let activeCertificates: [ALTCertificate]
        if let cachedActive = self.context.authenticatedContext.activeCertificates, !cachedActive.isEmpty {
            activeCertificates = cachedActive
            self.debugLog("[VerifyCertificateOperation] Utilizing \(activeCertificates.count) active certificates cached from Auth context.")
        } else {
            self.debugLog("[VerifyCertificateOperation] Active certificates not found in Auth context. Fetching live from Apple Developer Portal...")
            activeCertificates = try await ALTAppleAPI.shared.fetchCertificates(for: team, session: session)
            self.context.authenticatedContext.activeCertificates = activeCertificates
        }
        
        self.setProgress(30)
        
        let bundleID = self.context.targetBundleIdentifier
        let activeKeychainCert = CertificateManager.shared.activeCertificate
        let activeKeychainSerial = activeKeychainCert?.serialNumber
        let authenticatedCertSerial = self.context.authenticatedContext.certificate?.serialNumber
        let overrideCertSerial = self.context.overrideCertificate?.serialNumber
        
        // 2. Fetch InstalledApp details from CoreData
        let (appName, installedAppSerial) = await self.fetchInstalledAppDetails(bundleID: bundleID)
        
        self.setProgress(50)
        
        let activeSerials = Set(activeCertificates.compactMap { $0.serialNumber })
        
        debugLog("""
        [VerifyCertificateOperation] Parameter Accountability for '\(appName)' (\(bundleID)):
          • installedAppSerial           : \(installedAppSerial ?? "nil")
          • overrideCertSerial           : \(overrideCertSerial ?? "nil")
          • authenticatedCertSerial      : \(authenticatedCertSerial ?? "nil")
          • activeKeychainSerial         : \(activeKeychainSerial ?? "nil")
          • portalActiveSerials (\(activeSerials.count))  : \(Array(activeSerials))
        """)
        
        struct Candidate {
            let name: String
            let serial: String?
        }
        
        let candidates: [Candidate] = [
            Candidate(name: "overrideCertificate", serial: overrideCertSerial),
            Candidate(name: "installedAppSerial", serial: installedAppSerial),
            Candidate(name: "authenticatedContext.certificate", serial: authenticatedCertSerial)
        ].compactMap { candidate in
            guard let serial = candidate.serial, !serial.isEmpty else {
                debugLog("[VerifyCertificateOperation] Candidate [\(candidate.name)] is nil or empty. Skipping.")
                return nil
            }
            debugLog("[VerifyCertificateOperation] Candidate [\(candidate.name)] present: '\(serial)'")
            return candidate
        }
        
        let candidateSummary = candidates.map { "\($0.name) ('\($0.serial ?? "")')" }.joined(separator: ", ")
        debugLog("[VerifyCertificateOperation] Processing \(candidates.count) candidate certificate(s) in priority order for '\(appName)': [\(candidateSummary)]")
        
        var selectedValidSerial: String? = nil
        var selectedCandidateName: String? = nil
        var finalIsCrossSigned = false
        
        let candidateCount = max(candidates.count, 1)
        for (index, candidate) in candidates.enumerated() {
            guard let serial = candidate.serial else { continue }
            debugLog("[VerifyCertificateOperation] ---> Testing candidate [\(candidate.name)]: '\(serial)'...")
            let result = validateCandidate(serial: serial, portalActiveSerials: activeSerials, activeKeychainSerial: activeKeychainSerial)
            
            let currentProgress = 50 + Int64((Double(index + 1) / Double(candidateCount)) * 40.0)
            self.setProgress(currentProgress)
            
            switch result {
            case .valid(let isCrossSigned):
                debugLog("[VerifyCertificateOperation] SELECTED VALID CERTIFICATE: Candidate [\(candidate.name)] with serial '\(serial)' (isCrossSigned: \(isCrossSigned))")
                selectedValidSerial = serial
                selectedCandidateName = candidate.name
                finalIsCrossSigned = isCrossSigned
            case .revoked:
                debugLog("[VerifyCertificateOperation] WARN: Candidate [\(candidate.name)] serial '\(serial)' is REVOKED. Skipping to next candidate...")
            }
            
            if selectedValidSerial != nil {
                break
            }
        }
        
        if let verifiedSerial = selectedValidSerial, let candidateName = selectedCandidateName {
            debugLog("[VerifyCertificateOperation] Final Verified Result for '\(appName)': Selected '\(candidateName)' with serial '\(verifiedSerial)' (isCrossSigned: \(finalIsCrossSigned))")
            await self.updateAppState(bundleID: bundleID, isRevoked: false, isCrossSigned: finalIsCrossSigned)
            self.setProgress(100)
        } else {
            debugLog("[VerifyCertificateOperation] FAILURE: All candidate certificates for app '\(appName)' are REVOKED!")
            await self.updateAppState(bundleID: bundleID, isRevoked: true, isCrossSigned: false)
            self.setProgress(100)
            throw OperationError.certificateRevoked(appName: appName)
        }
    }


    private func validateCandidate(serial: String,
                                   portalActiveSerials: Set<String>,
                                   activeKeychainSerial: String?) -> CertificateValidationResult {
        debugLog("[VerifyCertificateOperation] Validating candidate serial '\(serial)'...")
        
        // Tier 1: Apple Developer Portal check
        if portalActiveSerials.contains(serial) {
            let isCrossSigned = (activeKeychainSerial != nil && !activeKeychainSerial!.isEmpty && serial != activeKeychainSerial)
            debugLog("[VerifyCertificateOperation] Tier 1: Candidate serial '\(serial)' is ACTIVE on Apple Developer Portal. (isCrossSigned: \(isCrossSigned))")
            return .valid(isCrossSigned: isCrossSigned)
        }
        

        // Tier 2: Apple OCSP check for external/borrowed certs
        debugLog("[VerifyCertificateOperation] Tier 2: Candidate serial '\(serial)' not in portal active list. Checking Apple OCSP (ocsp.apple.com)...")
        
        var certToTest = CertificateManager.shared.loadCertificate(for: serial)
            ?? (self.context.overrideCertificate?.serialNumber == serial ? self.context.overrideCertificate : (self.context.authenticatedContext.certificate?.serialNumber == serial ? self.context.authenticatedContext.certificate : nil))
        
        if certToTest == nil, let app = self.context.app {
            let profileURL = app.fileURL.appendingPathComponent("embedded.mobileprovision")
            if let bundleCert = CertificateManager.shared.loadCertificate(fromProvisioningProfileAt: profileURL), bundleCert.serialNumber == serial {
                certToTest = bundleCert
            }
        }
        
        guard let cert = certToTest else {
            debugLog("[VerifyCertificateOperation] Tier 2: Candidate serial '\(serial)' has no local certificate data. Marking as REVOKED.")
            return .revoked
        }
        
        let isRevoked = checkRevocationWithOCSP(certificate: cert)
        if isRevoked {
            debugLog("[VerifyCertificateOperation] Tier 2: Candidate serial '\(serial)' is CONFIRMED REVOKED by Apple OCSP.")
            return .revoked
        } else {
            debugLog("[VerifyCertificateOperation] Tier 2: Candidate serial '\(serial)' is VALID (3rd-party/borrowed cert). Marking as Cross-Signed.")
            return .valid(isCrossSigned: true)
        }
    }
    
    private func checkRevocationWithOCSP(certificate: ALTCertificate) -> Bool {
        verboseLog("[VerifyCertificateOperation] checkRevocationWithOCSP started for cert serial: \(certificate.serialNumber)")
        
        guard let data = certificate.data,
              let secCert = SecCertificateCreateWithData(nil, data as CFData) else {
            verboseLog("[VerifyCertificateOperation] checkRevocationWithOCSP: Failed to parse SecCertificate from certificate data.")
            return false
        }
        
        let policy = SecPolicyCreateBasicX509()
        var optionalTrust: SecTrust?
        let status = SecTrustCreateWithCertificates(secCert, policy, &optionalTrust)
        guard status == errSecSuccess, let trust = optionalTrust else {
            verboseLog("[VerifyCertificateOperation] checkRevocationWithOCSP: SecTrustCreateWithCertificates failed with status: \(status)")
            return false
        }
        
        if let revocationPolicy = SecPolicyCreateRevocation(CFOptionFlags(kSecRevocationOCSPMethod | kSecRevocationCRLMethod)) {
            SecTrustSetPolicies(trust, revocationPolicy)
            verboseLog("[VerifyCertificateOperation] checkRevocationWithOCSP: Configured SecTrust with OCSP & CRL revocation policies.")
        }
        
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)
        verboseLog("[VerifyCertificateOperation] checkRevocationWithOCSP: SecTrustEvaluateWithError returned isValid: \(isValid)")
        
        if !isValid, let err = error as Error? as NSError? {
            verboseLog("[VerifyCertificateOperation] checkRevocationWithOCSP error: code \(err.code), domain: \(err.domain), description: '\(err.localizedDescription)'")
            if err.code == -67820 || err.localizedDescription.lowercased().contains("revoked") {
                debugLog("[VerifyCertificateOperation] checkRevocationWithOCSP: Certificate serial \(certificate.serialNumber) is CONFIRMED REVOKED by Apple OCSP!")
                return true
            }
        }
        
        verboseLog("[VerifyCertificateOperation] checkRevocationWithOCSP: Certificate serial \(certificate.serialNumber) is valid or unconfirmed.")
        return false
    }
    
    private func fetchInstalledAppDetails(bundleID: String) async -> (appName: String, installedAppSerial: String?) {
        await DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) -> (String, String?) in
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
            if let installedApp = InstalledApp.first(satisfying: predicate, in: context) {
                return (installedApp.name, installedApp.certificateSerialNumber)
            }
            return (bundleID, nil)
        }
    }

    private func updateAppState(bundleID: String, isRevoked: Bool, isCrossSigned: Bool) async {
        verboseLog("[VerifyCertificateOperation] updateAppState called for bundleID: \(bundleID), isRevoked: \(isRevoked), isCrossSigned: \(isCrossSigned)")
        await MainActor.run {
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
            if let app = InstalledApp.first(satisfying: predicate, in: DatabaseManager.shared.viewContext) {
                app.isRevoked = isRevoked
                app.isCrossSigned = isCrossSigned
                try? DatabaseManager.shared.viewContext.save()
                DatabaseManager.shared.viewContext.processPendingChanges()
                verboseLog("[VerifyCertificateOperation] updateAppState: CoreData updated successfully for app '\(app.name)' (\(bundleID)).")
            } else {
                verboseLog("[VerifyCertificateOperation] updateAppState: App with bundleID '\(bundleID)' not found in CoreData viewContext.")
            }
        }
    }
}
