//
//  PrepareAppExtensionBundleIDsOperation.swift
//  SideStore
//
//  Created by Magesh K on 01/08/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation
import AltStoreCore

final class PrepareAppExtensionBundleIDsOperation: BasePipelineOperation<AppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        debugLog("[PrepareAppExtensionBundleIDsOperation] execute() started")
        defer { debugLog("[PrepareAppExtensionBundleIDsOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        if self.context.useMainProfile {
            if let app = self.context.app, let profile = self.context.provisioningProfiles?[self.context.bundleIdentifier] {
                var appexBundleIds: [String: String] = [:]
                for appex in app.appExtensions {
                    appexBundleIds[appex.bundleIdentifier] = appex.bundleIdentifier
                        .replacingOccurrences(of: app.bundleIdentifier, with: profile.bundleIdentifier)
                }
                self.context.appexBundleIds = appexBundleIds
            }
        }
        self.setProgress(100)
    }
}
