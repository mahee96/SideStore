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
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class VerifyCertificateOperation: BasePipelineOperation<AppOperationContext, Void>, @unchecked Sendable {
    
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
        
        self.setProgress(40)
        
        let bundleID = self.context.targetBundleIdentifier
        let activeKeychainCert = self.context.certificate ?? Keychain.shared.certificate
        let activeKeychainSerial = activeKeychainCert?.serialNumber
        
        // 2. Fetch InstalledApp details from CoreData
        let (appName, installedAppSerial) = await DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) -> (String, String?) in
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
            if let installedApp = InstalledApp.first(satisfying: predicate, in: context) {
                return (installedApp.name, installedApp.certificateSerialNumber)
            }
            return (bundleID, nil)
        }
        
        let targetSerial = installedAppSerial ?? activeKeychainSerial
        
        if let serial = targetSerial, !serial.isEmpty {
            let activeSerials = Set(activeCertificates.compactMap { $0.serialNumber })
            
            // Check 1: Was the certificate used to install this app REVOKED on Apple Developer Portal?
            if !activeSerials.contains(serial) {
                debugLog("[VerifyCertificateOperation] Certificate used for '\(appName)' (serial: \(serial)) was REVOKED on Apple Developer Portal!")
                throw OperationError.certificateRevoked(appName: appName)
            }
            
            // Check 2: Does the certificate used to install this app DIFFER from the current active signing certificate?
            if let currentSerial = activeKeychainSerial, !currentSerial.isEmpty, serial != currentSerial {
                debugLog("[VerifyCertificateOperation] Certificate used for '\(appName)' (serial: \(serial)) DIFFERS from current active certificate (serial: \(currentSerial)).")
                throw OperationError.certificateChanged(appName: appName)
            }
        }
        
        self.setProgress(80)
        
        // 3. Verify newly fetched provisioning profile certificates if present
        if let profiles = self.context.provisioningProfiles {
            let activeSerials = Set(activeCertificates.compactMap { $0.serialNumber })
            for profile in profiles.values {
                for cert in profile.certificates {
                    let serial = cert.serialNumber
                    if !serial.isEmpty && !activeSerials.contains(serial) {
                        debugLog("[VerifyCertificateOperation] Provisioning profile certificate for '\(appName)' (serial: \(serial)) was REVOKED on Apple Developer Portal!")
                        throw OperationError.certificateRevoked(appName: appName)
                    }
                }
            }
        }
        
        debugLog("[VerifyCertificateOperation] Certificate verification PASSED for '\(appName)'.")
        self.setProgress(100)
    }
}
