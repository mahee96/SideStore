//
//  EmbedSigningCertOperation.swift
//  SideStore
//
//  Created by Magesh K on 8/5/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import AltStoreCore
import AltSign

final class EmbedSigningCertOperation: BasePipelineOperation<AppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        debugLog("[EmbedSigningCertOperation] execute() started")
        defer { debugLog("[EmbedSigningCertOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        let bundleID = self.context.targetBundleIdentifier
        
        // 1. Resolve the certificate used for signing this app
        guard let cert = self.context.overrideCertificate ?? self.context.authenticatedContext.signingCertificate else
        {
            throw OperationError.invalidParameters("EmbedSigningCertOperation: No signing certificate found in context.")
        }
        
        guard let certData = cert.data else {
            debugLog("[EmbedSigningCertOperation] WARNING: Certificate has no data to embed.")
            return
        }
        
        // 2. Write signing_certificate.der directly inside the target app bundle
        guard let appBundle = self.context.targetAppBundle else {
            throw OperationError.invalidParameters("EmbedSigningCertOperation: targetAppBundle is missing in context.")
        }
        
        let bundleCertURL = appBundle.fileURL.appendingPathComponent("signing_certificate.der")
        do {
            try certData.write(to: bundleCertURL, options: .atomic)
            debugLog("[EmbedSigningCertOperation] Successfully embedded signing certificate in app bundle: \(bundleCertURL.path)")
        } catch {
            debugLog("[EmbedSigningCertOperation] ERROR: Failed to embed signing certificate into app bundle: \(error)")
            throw error
        }
    }
}
