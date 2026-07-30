//
//  CacheAppOperation.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation
@preconcurrency import AltStoreCore

final class CacheAppOperation: BaseOperation<InstallAppOperationContext, URL?>, @unchecked Sendable {

    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> URL? {
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)

        guard let app = context.app else {
            debugLog("[CacheAppOperation] context.app is nil")
            return nil
        }

        let updatedApp = AnyApp(from: app, bundleId: context.targetBundleIdentifier)
        let targetFileURL = InstalledApp.fileURL(for: updatedApp)
        try FileManager.default.copyItem(at: app.fileURL, to: targetFileURL, shouldReplace: true)
        return targetFileURL
    }
}
