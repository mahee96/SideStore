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
        
        let activeSerials = Set(activeCertificates.compactMap { $0.serialNumber })
        debugLog("""
        [VerifyCertificateOperation] Verifying App: '\(appName)' (\(bundleID))
          • Installed App Serial : \(installedAppSerial ?? "nil")
          • Active Keychain Serial: \(activeKeychainSerial ?? "nil")
          • Portal Active Serials : \(Array(activeSerials))
        
        """)
        
        let targetSerial = installedAppSerial ?? activeKeychainSerial
        
        if let serial = targetSerial, !serial.isEmpty {
            // Check 1: Was the certificate used to install this app REVOKED on Apple Developer Portal?
            if !activeSerials.contains(serial) {
                debugLog("[VerifyCertificateOperation] Certificate used for '\(appName)' (serial: \(serial)) was REVOKED on Apple Developer Portal!")
                
                await MainActor.run {
                    let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
                    if let app = InstalledApp.first(satisfying: predicate, in: DatabaseManager.shared.viewContext) {
                        app.isRevoked = true
                        app.isCrossSigned = false
                        try? DatabaseManager.shared.viewContext.save()
                        DatabaseManager.shared.viewContext.processPendingChanges()
                    }
                }
                
                throw OperationError.certificateRevoked(appName: appName)
            }
            
            // Check 2: Does the certificate used to install this app DIFFER from the current active signing certificate?
            if let currentSerial = activeKeychainSerial, !currentSerial.isEmpty, serial != currentSerial {
                debugLog("[VerifyCertificateOperation] Certificate used for '\(appName)' (serial: \(serial)) DIFFERS from current active certificate (serial: \(currentSerial)).")
                
                await MainActor.run {
                    let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
                    if let app = InstalledApp.first(satisfying: predicate, in: DatabaseManager.shared.viewContext) {
                        app.isRevoked = false
                        app.isCrossSigned = true
                        try? DatabaseManager.shared.viewContext.save()
                        DatabaseManager.shared.viewContext.processPendingChanges()
                    }
                }
                
                throw OperationError.certificateChanged(appName: appName)
            }
        }
        
        self.setProgress(80)
        
        // 3. Verify newly fetched provisioning profile certificates if present
        if let profiles = self.context.provisioningProfiles {
            for profile in profiles.values {
                for cert in profile.certificates {
                    let serial = cert.serialNumber
                    if !serial.isEmpty && !activeSerials.contains(serial) {
                        debugLog("[VerifyCertificateOperation] Provisioning profile certificate for '\(appName)' (serial: \(serial)) was REVOKED on Apple Developer Portal!")
                        
                        await MainActor.run {
                            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
                            if let app = InstalledApp.first(satisfying: predicate, in: DatabaseManager.shared.viewContext) {
                                app.isRevoked = true
                                app.isCrossSigned = false
                                try? DatabaseManager.shared.viewContext.save()
                                DatabaseManager.shared.viewContext.processPendingChanges()
                            }
                        }
                        
                        throw OperationError.certificateRevoked(appName: appName)
                    }
                }
            }
        }
        
        // Success case: clear flags
        await MainActor.run {
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
            if let app = InstalledApp.first(satisfying: predicate, in: DatabaseManager.shared.viewContext) {
                app.isRevoked = false
                app.isCrossSigned = false
                try? DatabaseManager.shared.viewContext.save()
                DatabaseManager.shared.viewContext.processPendingChanges()
            }
        }
        
        debugLog("[VerifyCertificateOperation] Certificate verification PASSED for '\(appName)' (serial: \(installedAppSerial ?? "nil")).")
        self.setProgress(100)
    }
}
