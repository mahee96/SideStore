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
    private let willResign: Bool
    
    init(context: AppOperationContext, willResign: Bool = true) throws {
        self.willResign = willResign
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?) async throws {
        debugLog("[VerifyCertificateOperation] execute() started (willResign: \(self.willResign))")
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        guard let team = self.context.authenticatedContext.team, let session = self.context.authenticatedContext.session else {
            debugLog("[VerifyCertificateOperation] Skipping certificate verification: team or session missing in context.")
            self.setProgress(100)
            throw OperationError.notAuthenticated
        }
        
        let bundleID = self.context.targetBundleIdentifier
        let (appName, installedAppSerial, initialStatus) = await self.fetchInstalledAppInitialState(bundleID: bundleID)
        var finalStatus = initialStatus
        
        do {
            // 2. Obtain active portal certificates (auth context or direct fetch as fallback)
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
            
            let portalCertificateSerials = Set(activeCertificates.compactMap { $0.serialNumber })
            let signingCertificateSerial = self.context.overrideCertificate?.serialNumber ?? CertificateManager.shared.activeCertificate?.serialNumber
            
            debugLog("""
            [VerifyCertificateOperation] Parameter Accountability for '\(appName)' (\(bundleID)):
              • installedAppSerial           : \(installedAppSerial ?? "nil")
              • overrideCertSerial           : \(self.context.overrideCertificate?.serialNumber ?? "nil")
              • authenticatedCertSerial      : \(self.context.authenticatedContext.certificate?.serialNumber ?? "nil")
              • signingCertificateSerial     : \(signingCertificateSerial ?? "nil")
              • portalCertificateSerials (\(portalCertificateSerials.count))  : \(Array(portalCertificateSerials))
              • willResign                   : \(self.willResign)
            """)
            
            if !willResign {
                debugLog("[VerifyCertificateOperation] Running in verification-only mode (!willResign) for '\(appName)'...")
                
                guard let appBundle = self.context.targetAppBundle else {
                    throw OperationError.invalidApp
                }
                guard let binaryCert = CertificateManager.shared.getSigningCertificate(at: appBundle.fileURL) else {
                    throw OperationError.invalidApp
                }
                
                let result = validateCertificate(binaryCert, portalCertificateSerials: portalCertificateSerials, signingCertificateSerial: signingCertificateSerial)
                finalStatus = result
                self.context.targetCertStatus = result
                try processValidationResult(result, description: "Target bundle binary certificate", appName: appName)
                
            } else {
                // resigning branch
                debugLog("[VerifyCertificateOperation] Running in signing mode (resigning) for '\(appName)'...")
                
                let certType = self.context.overrideCertificate != nil ? "Override" : "Active"
                guard let target = self.context.overrideCertificate ?? CertificateManager.shared.activeCertificate?.certificate else {
                    throw OperationError.invalidParameters("\(certType) certificate is missing.")
                }
                guard target.privateKey != nil else {
                    throw OperationError.invalidParameters("\(certType) certificate lacks a private key.")
                }
                
                let result = validateCertificate(target, portalCertificateSerials: portalCertificateSerials, signingCertificateSerial: signingCertificateSerial)
                finalStatus = result
                self.context.targetCertStatus = result
                try processValidationResult(result, description: "Target signing certificate", appName: appName)
            }
            
            await self.persistStateIfChanged(bundleID: bundleID, status: finalStatus, initialStatus: initialStatus)
            self.setProgress(100)
        } catch {
            await self.persistStateIfChanged(bundleID: bundleID, status: finalStatus, initialStatus: initialStatus)
            throw error
        }
    }

    private func validateCertificate(_ certificate: ALTCertificate,
                                     portalCertificateSerials: Set<String>,
                                     signingCertificateSerial: String?) -> CertificateStatus {
        if portalCheck(certificate, portalCertificateSerials: portalCertificateSerials) 
        {
            let isCrossSigned = (signingCertificateSerial != nil && !signingCertificateSerial!.isEmpty && certificate.serialNumber != signingCertificateSerial)
            debugLog("[VerifyCertificateOperation] validateCertificate: Found in portal (isCrossSigned: \(isCrossSigned)).")
            return .valid(isCrossSigned: isCrossSigned)
        }
        
        debugLog("[VerifyCertificateOperation] validateCertificate: Not in portal active list. Falling back to OCSP check...")
        return OcspCheck(certificate)
    }
    

    private func portalCheck(_ certificate: ALTCertificate, portalCertificateSerials: Set<String>) -> Bool {
        return portalCertificateSerials.contains(certificate.serialNumber)
    }

    private func OcspCheck(_ certificate: ALTCertificate) -> CertificateStatus {
        if certificate.expiryDate <= Date() {
            debugLog("[VerifyCertificateOperation] OcspCheck: Certificate \(certificate.serialNumber) is EXPIRED.")
            return .expired
        }
        if checkRevocationWithOCSP(certificate: certificate) {
            debugLog("[VerifyCertificateOperation] OcspCheck: Certificate \(certificate.serialNumber) is REVOKED.")
            return .revoked
        }
        debugLog("[VerifyCertificateOperation] OcspCheck: Certificate \(certificate.serialNumber) is valid (assuming cross-signed).")
        return .valid(isCrossSigned: true)
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
    
    private func fetchInstalledAppInitialState(bundleID: String) async -> (name: String, serial: String?, status: CertificateStatus) {
         await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
             let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
             if let installedApp = InstalledApp.first(satisfying: predicate, in: context) {
                 return (installedApp.name, installedApp.certificateSerialNumber, installedApp.certificateStatus)
             }
             return (bundleID, nil, .valid(isCrossSigned: false))
         }
    }
    
    private func persistStateIfChanged(bundleID: String, status: CertificateStatus, initialStatus: CertificateStatus) async {
        guard status != initialStatus else { return }
        
        if let installContext = self.context as? InstallAppOperationContext,
           let installedApp = installContext.installedApp {
            installedApp.certificateStatus = status
        }
        
        await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
            guard let installedApp = InstalledApp.first(satisfying: predicate, in: context) else {
                self.debugLog("[VerifyCertificateOperation] persistStateIfChanged: App with bundleID '\(bundleID)' not found in database.")
                return
            }
            
            if installedApp.certificateStatus != status {
                self.debugLog("[VerifyCertificateOperation] State changed in database context for \(installedApp.name). New Status: \(status)")
                installedApp.certificateStatus = status
                do {
                    try context.save()
                    self.debugLog("[VerifyCertificateOperation] Saved background context successfully.")
                } catch {
                    self.debugLog("[VerifyCertificateOperation] Failed to save background context: \(error)")
                }
            }
        }
    }
    
    private func processValidationResult(_ result: CertificateStatus, description: String, appName: String) throws {
        switch result {
        case .valid(let isCrossSigned):
            if isCrossSigned {
                debugLog("[VerifyCertificateOperation] \(description) is VALID (cross-signed)")
            } else {
                debugLog("[VerifyCertificateOperation] \(description) is VALID")
            }
        case .revoked:
            debugLog("[VerifyCertificateOperation] \(description) is REVOKED")
            throw OperationError.certificateRevoked(appName: appName)
        case .expired:
            debugLog("[VerifyCertificateOperation] \(description) is EXPIRED")
            throw OperationError.certificateExpired(appName: appName)
        }
    }
}
