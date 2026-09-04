//
//  SendAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import Network
import SideSign

final class SendAppOperation: BasePipelineOperation<InstallAppOperationContext, ALTApplication>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws -> ALTApplication {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[SendAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[SendAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        guard let resignedAppBundle = self.context.resignedAppBundle else {
            throw OperationError.invalidParameters("SendAppOperation.main: self.resignedAppBundle is nil")
        }

        let bundleIdentifier = self.context.targetBundleIdentifier
        let appURL = resignedAppBundle.fileURL
        verboseLog("[SendAppOperation] AFC App Bundle `fileURL`: \(appURL.absoluteString)")

        await CellularRefreshManager.shared.turnOffDataIfNeeded()
        
        
        do {
            try await sendAppBundleAfc(bundleIdentifier, at: appURL)
            self.setProgress(100)
        } catch {
            debugLog("[SendAppOperation] Failed to send app bundle at \(appURL): \(error)")
            throw OperationError.appNotFound(name: bundleIdentifier)
        }
        return resignedAppBundle
    }
}
