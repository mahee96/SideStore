//
//  CleanStagedAppOperation.swift
//  AltStore
//
//  Created by Magesh K on 31/7/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltStoreCore

final class CleanStagedAppOperation: BaseOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws {
        debugLog("[CleanStagedAppOperation] execute() started")
        defer { debugLog("[CleanStagedAppOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        
        let tempDir = self.context.temporaryDirectory
        debugLog("[CleanStagedAppOperation] Removing temporary staged app directory: \(tempDir)")
        
        if FileManager.default.fileExists(atPath: tempDir.path) {
            do {
                try FileManager.default.removeItem(at: tempDir)
                debugLog("[CleanStagedAppOperation] Successfully removed temporary staged app directory.")
            } catch {
                debugLog("[CleanStagedAppOperation] Failed to remove temporary staged app directory: \(error)")
            }
        }
    }
}
