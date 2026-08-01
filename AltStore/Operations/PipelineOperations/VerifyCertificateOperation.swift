//
//  VerifyCertificateOperation.swift
//  AltStore
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
    
    private func checkRevocationWithOCSP(certificate: ALTCertificate) -> Bool {
        guard let secCert = SecCertificateCreateWithData(nil, certificate.data as CFData) else {
            return false
        }
        
        let policy = SecPolicyCreateBasicX509()
        var optionalTrust: SecTrust?
        let status = SecTrustCreateWithCertificates(secCert, policy, &optionalTrust)
        guard status == errSecSuccess, let trust = optionalTrust else {
            return false
        }
        
        SecTrustSetPolicies(trust, SecPolicyCreateRevocation(kSecRevocationOCSPMethod | kSecRevocationCRLMethod))
        
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)
        
        if !isValid, let error = error as Error? as NSError? {
            if error.code == -67820 || error.domain == (kSecErrorDomain as String) {
                return true
            }
        }
        
        return false
    }
    
    private func updateAppState(bundleID: String, isRevoked: Bool, isCrossSigned: Bool) async {
        await MainActor.run {
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
            if let app = InstalledApp.first(satisfying: predicate, in: DatabaseManager.shared.viewContext) {
                app.isRevoked = isRevoked
                app.isCrossSigned = isCrossSigned
                try? DatabaseManager.shared.viewContext.save()
                DatabaseManager.shared.viewContext.processPendingChanges()
            }
        }
    }

    override func execute(parentProgress: Progress?) async throws {
        debugLog("[VerifyCertificateOperation] execute() started")
        defer { debugLog("[VerifyCertificateOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        guard let team = self.context.team, let session = self.context.session else {
            debugLog("[VerifyCertificateOperation] Skipping certificate verification: team or session missing in context.")
            self.setProgress(100)
            return
        }
        
        // 1. Obtain active portal certificates (from Auth context cache or fallback fetch)
        let activeCertificates: [ALTCertificate]
        if let cachedActive = self.context.activeCertificates, !cachedActive.isEmpty {
            activeCertificates = cachedActive
            self.debugLog("[VerifyCertificateOperation] Utilizing \(activeCertificates.count) active certificates cached from Auth context.")
        } else {
            self.debugLog("[VerifyCertificateOperation] Active certificates not found in Auth context. Fetching live from Apple Developer Portal...")
            activeCertificates = try await ALTAppleAPI.shared.fetchCertificates(for: team, session: session)
            self.context.authenticatedContext.activeCertificates = activeCertificates
        }
        
        self.setProgress(30)
        
        let bundleID = self.context.targetBundleIdentifier
        let activeKeychainCert = Keychain.shared.certificate ?? self.context.certificate
        let activeKeychainSerial = activeKeychainCert?.serialNumber
        
        // 2. Fetch InstalledApp details from CoreData
        let (appName, installedAppSerial) = await DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) -> (String, String?) in
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
            if let installedApp = InstalledApp.first(satisfying: predicate, in: context) {
                return (installedApp.name, installedApp.certificateSerialNumber)
            }
            return (bundleID, nil)
        }
        
        self.setProgress(50)
        
        let activeSerials = Set(activeCertificates.compactMap { $0.serialNumber })
        debugLog("""
        [VerifyCertificateOperation] Verifying App: '\(appName)' (\(bundleID))
          • Installed App Serial : \(installedAppSerial ?? "nil")
          • Active Keychain Serial: \(activeKeychainSerial ?? "nil")
          • Portal Active Serials : \(Array(activeSerials))
        
        """)
        
        let targetSerial = installedAppSerial ?? activeKeychainSerial
        
        if let serial = targetSerial, !serial.isEmpty {
            if activeSerials.contains(serial) {
                // Tier 1: Confirmed ACTIVE on logged-in Developer Portal!
                let isCrossSigned = (activeKeychainSerial != nil && !activeKeychainSerial!.isEmpty && serial != activeKeychainSerial)
                debugLog("[VerifyCertificateOperation] Certificate serial '\(serial)' is ACTIVE on Apple Developer Portal. (isCrossSigned: \(isCrossSigned))")
                
                await self.updateAppState(bundleID: bundleID, isRevoked: false, isCrossSigned: isCrossSigned)
                self.setProgress(90)
            } else {
                // Tier 2: Not in logged-in portal list (e.g. 3rd-party / borrowed cert or revoked cert).
                // Query Apple OCSP responder (ocsp.apple.com) directly!
                self.setProgress(70)
                debugLog("[VerifyCertificateOperation] Certificate serial '\(serial)' NOT found in logged-in portal list. Contacting Apple OCSP responder (ocsp.apple.com)...")
                
                let certToTest = (installedAppSerial == Keychain.shared.certificate?.serialNumber) ? Keychain.shared.certificate : self.context.certificate
                var isConfirmedRevoked = false
                
                if let cert = certToTest {
                    isConfirmedRevoked = checkRevocationWithOCSP(certificate: cert)
                }
                
                if isConfirmedRevoked {
                    debugLog("[VerifyCertificateOperation] Apple OCSP confirmed certificate serial '\(serial)' is REVOKED!")
                    await self.updateAppState(bundleID: bundleID, isRevoked: true, isCrossSigned: false)
                    throw OperationError.certificateRevoked(appName: appName)
                } else {
                    debugLog("[VerifyCertificateOperation] Apple OCSP check for serial '\(serial)' completed (Valid 3rd-party / borrowed cert). Marking as Cross-Signed.")
                    await self.updateAppState(bundleID: bundleID, isRevoked: false, isCrossSigned: true)
                }
            }
        }
        
        self.setProgress(100)
    }
}
