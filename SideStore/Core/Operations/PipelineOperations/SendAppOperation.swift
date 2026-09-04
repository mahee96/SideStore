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

        let app = AnyApp(name: resignedAppBundle.name, bundleIdentifier: self.context.targetBundleIdentifier, url: resignedAppBundle.fileURL, storeApp: nil)
        verboseLog("[SendAppOperation] AFC App Bundle `fileURL`: \(resignedAppBundle.fileURL.absoluteString)")

        // Cellular shortcut should only be executed below iOS 16.4 AND when explicitly enabled in settings
        if #available(iOS 16.4, *) {
            context.shouldTurnOffData = false
        } else {
            context.shouldTurnOffData = UserDefaults.standard.isCellularRefreshEnabled
        }
        
        if self.context.shouldTurnOffData {
            // Wait for Shortcut to Finish Before Proceeding
            let shortcutURLoff = URL(string: "shortcuts://run-shortcut?name=TurnOffData")!
            await UIApplication.shared.open(shortcutURLoff)
            self.debugLog("[SendAppOperation] Shortcut finished execution. Proceeding with file transfer.")
        }
        
        
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
