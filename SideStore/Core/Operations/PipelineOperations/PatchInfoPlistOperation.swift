//
//  PatchInfoPlistOperation.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

final class PatchInfoPlistOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[PatchInfoPlistOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[PatchInfoPlistOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        let bundleID = self.context.installedApp?.bundleIdentifier ?? self.context.targetBundleIdentifier
        
        guard let targetAppBundle = self.context.targetAppBundle else {
            debugLog("[PatchInfoPlistOperation] No targetAppBundle found. Skipping.")
            return
        }

        for bundle in targetAppBundle.allAppBundles {
            let targetID = bundle.bundleIdentifier
            guard let plistURL = InstalledApp.customInfoPlistURL(forBundleIdentifier: bundleID, targetID: targetID) else {
                continue
            }
            
            do {
                let customParser = try InfoPlistParser(plistURL: plistURL)
                self.context.customInfoPlistByBundleID[targetID] = customParser.rawDictionary
                
                if bundle == targetAppBundle {
                    if let customID = customParser.bundleIdentifier,
                       !customID.isEmpty,
                       customID != self.context.bundleIdentifier {
                        self.context.customBundleIdentifier = customID
                    }
                }
                
                try bundle.updateInfoPlist(with: customParser.rawDictionary)
                debugLog("[PatchInfoPlistOperation] Successfully patched Info.plist for \(targetID) from \(plistURL.lastPathComponent)")
            } catch {
                debugLog("[PatchInfoPlistOperation] Error applying custom Info.plist for \(targetID): \(error)")
                throw error
            }
        }
    }
}
