//
//  VerifyCertificateOperation.swift
//  AltStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
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
            self.context.activeCertificates = activeCertificates
        }
        
        self.setProgress(50)
        
        // 2. Identify target certificate serial numbers (from newly fetched provisioning profiles or context certificate)
        var targetSerialNumbers: Set<String> = []
        
        if let profiles = self.context.provisioningProfiles {
            for profile in profiles.values {
                for cert in profile.certificates {
                    if let serial = cert.serialNumber, !serial.isEmpty {
                        targetSerialNumbers.insert(serial)
                    }
                }
            }
        }
        
        if targetSerialNumbers.isEmpty, let appProfile = self.context.app?.provisioningProfile {
            for cert in appProfile.certificates {
                if let serial = cert.serialNumber, !serial.isEmpty {
                    targetSerialNumbers.insert(serial)
                }
            }
        }
        
        if targetSerialNumbers.isEmpty {
            if let cert = self.context.certificate ?? Keychain.shared.certificate, let serial = cert.serialNumber, !serial.isEmpty {
                targetSerialNumbers.insert(serial)
            }
        }
        
        guard !targetSerialNumbers.isEmpty else {
            debugLog("[VerifyCertificateOperation] No signing certificate serial numbers found to verify. Skipping.")
            self.setProgress(100)
            return
        }
        
        self.setProgress(80)
        
        let activeSerials = Set(activeCertificates.compactMap { $0.serialNumber })
        let revokedSerials = targetSerialNumbers.subtracting(activeSerials)
        
        if !revokedSerials.isEmpty {
            let revokedList = Array(revokedSerials).joined(separator: ", ")
            debugLog("[VerifyCertificateOperation] Signing Certificate (serial: \(revokedList)) is REVOKED or no longer active on Apple Developer Portal!")
            throw OperationError.invalidCertificate(revokedList)
        }
        
        debugLog("[VerifyCertificateOperation] All profile signing certificates (serials: \(Array(targetSerialNumbers).joined(separator: ", "))) are VALID and active on Apple Developer Portal.")
        self.setProgress(100)
    }
}
