//
//  UserCustomizationOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//


import Foundation
final class UserCustomizationOperation: BasePipelineOperation<InstallAppOperationContext, String?>, @unchecked Sendable {

    override func execute(parentProgress: Progress?) async throws -> String? {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[UserCustomizationOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[UserCustomizationOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        let handler = context.handler.userCustomizationHandler

        if UserDefaults.standard.customizeInfoPlist {
            let initialPlist: [String: Any] = {
                if let targetAppBundle = context.targetAppBundle,
                   let dict = targetAppBundle.bundle.completeInfoDictionary ?? (NSDictionary(contentsOf: targetAppBundle.bundle.infoPlistURL) as? [String: Any]) {
                    return dict
                }
                return ["CFBundleIdentifier": context.targetBundleIdentifier]
            }()

            let initialBundleID = context.targetBundleIdentifier
            self.setProgress(40)

            guard let result = try await handler.resolveInfoPlistCustomization(
                initialPlist: initialPlist,
                initialBundleID: initialBundleID,
                appendTeamID: context.appendTeamID
            ) else {
                throw OperationError.cancelled
            }

            context.customInfoPlist = result.modifiedPlist
            context.appendTeamID = result.appendTeamID

            if let customID = result.modifiedPlist["CFBundleIdentifier"] as? String,
               !customID.isEmpty,
               customID != context.bundleIdentifier {
                context.customBundleIdentifier = customID
            } else {
                context.customBundleIdentifier = nil
            }

            if let targetAppBundle = context.targetAppBundle {
                if var currentDict = (NSDictionary(contentsOf: targetAppBundle.bundle.infoPlistURL) as? [String: Any]) {
                    for (k, v) in result.modifiedPlist {
                        currentDict[k] = v
                    }
                    (currentDict as NSDictionary).write(to: targetAppBundle.bundle.infoPlistURL, atomically: true)
                }
            }

            self.setProgress(100)
            return context.targetBundleIdentifier
        } else if UserDefaults.standard.customizeAppId {
            let initialBundleID = context.targetBundleIdentifier
            self.setProgress(40)
            
            guard let result = try await handler.resolveBundleIDOverride(initialBundleID: initialBundleID) else {
                throw OperationError.cancelled
            }
            
            context.appendTeamID = result.appendTeamID
            if result.customID != context.bundleIdentifier {
                context.customBundleIdentifier = result.customID
            } else {
                context.customBundleIdentifier = nil
            }

            self.setProgress(100)
            return context.targetBundleIdentifier
        } else {
            self.setProgress(100)
            return nil
        }
    }
}
