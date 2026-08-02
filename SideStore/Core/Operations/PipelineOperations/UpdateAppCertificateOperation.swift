//
//  UpdateAppCertificateOperation.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import CoreData
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class UpdateAppCertificateOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws {
        debugLog("[UpdateAppCertificateOperation] execute() started")
        defer { debugLog("[UpdateAppCertificateOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        if let installedApp = self.context.installedApp, let serialNumber = installedApp.certificateSerialNumber {
            debugLog("[UpdateAppCertificateOperation] InstalledApp '\(installedApp.name)' has custom certificate serial: '\(serialNumber)'")
            if let customCert = CertificateManager.shared.loadCertificate(for: serialNumber) {
                debugLog("[UpdateAppCertificateOperation] Loaded custom certificate '\(customCert.serialNumber)' for app '\(installedApp.name)'. Setting context.overrideCertificate.")
                self.context.overrideCertificate = customCert
            } else {
                debugLog("[UpdateAppCertificateOperation] WARNING: Custom certificate serial '\(serialNumber)' not found in local cache for app '\(installedApp.name)'.")
            }
        }
        
        self.setProgress(100)
    }
}
