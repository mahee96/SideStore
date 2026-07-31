//
//  StageAppOperation.swift
//  AltStore
//
//  Created by Magesh K on 31/7/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class StageAppOperation: BaseOperation<InstallAppOperationContext, ALTApplication>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> ALTApplication {
        debugLog("[StageAppOperation] execute() started")
        defer { debugLog("[StageAppOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        
        guard let app = self.context.app else {
            throw OperationError.invalidParameters("StageAppOperation: context.app is nil")
        }
        
        let fileURL = app.fileURL
        let tempDir = self.context.temporaryDirectory
        
        if fileURL.path.hasPrefix(tempDir.path) {
            debugLog("[StageAppOperation] App is already in temporary directory: \(fileURL)")
            return app
        }
        
        let destinationURL = tempDir.appendingPathComponent(fileURL.lastPathComponent)
        debugLog("[StageAppOperation] Copying cached app from \(fileURL) to \(destinationURL)")
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            debugLog("[StageAppOperation] Removing pre-existing app bundle at destination: \(destinationURL)")
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        debugLog("[StageAppOperation] Copying item from \(fileURL) to \(destinationURL)")
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
        debugLog("[StageAppOperation] Successfully copied app bundle to destination.")
        
        guard let stagedApp = ALTApplication(fileURL: destinationURL) else {
            throw OperationError.invalidApp
        }
        
        self.context.app = stagedApp
        return stagedApp
    }
}
