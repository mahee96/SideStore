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

    override func execute(parentProgress: Progress?) async throws -> URL? {
        debugLog("[CacheAppOperation] execute() started")
        defer { debugLog("[CacheAppOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        guard let app = context.app else {
            debugLog("[CacheAppOperation] context.app is nil")
            self.setProgress(100)
            return nil
        }

        self.setProgress(40)
        let updatedApp = AnyApp(from: app, bundleId: context.targetBundleIdentifier)
        let targetFileURL = InstalledApp.fileURL(for: updatedApp)
        
        self.setProgress(70)
        try FileManager.default.copyItem(at: app.fileURL, to: targetFileURL, shouldReplace: true)
        
        self.setProgress(100)
        return targetFileURL
    }
}
