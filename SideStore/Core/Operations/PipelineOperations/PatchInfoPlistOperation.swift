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
        
        guard let targetAppBundle = self.context.targetAppBundle else {
            debugLog("[PatchInfoPlistOperation] No targetAppBundle found. Skipping.")
            return
        }

        for bundle in targetAppBundle.allAppBundles {
            let isMain = (bundle == targetAppBundle)
            
            // 1. If not already in context, load from installedApp's cache
            if self.context.customInfoPlistByBundleID[bundle.bundleIdentifier] == nil {
                let resignedID = isMain
                    ? self.context.installedApp?.resignedBundleIdentifier
                    : self.context.installedApp?.appExtensions.first(where: { $0.bundleIdentifier == bundle.bundleIdentifier })?.resignedBundleIdentifier
                
                if let resignedID,
                   let plistURL = self.context.installedApp?.customInfoPlistURL(forResignedID: resignedID),
                   let customParser = try? InfoPlistParser(plistURL: plistURL) {
                    self.context.customInfoPlistByBundleID[bundle.bundleIdentifier] = customParser.rawDictionary
                }
            }
            
            if self.context.customEntitlementsByBundleID[bundle.bundleIdentifier] == nil {
                let resignedID = isMain
                    ? self.context.installedApp?.resignedBundleIdentifier
                    : self.context.installedApp?.appExtensions.first(where: { $0.bundleIdentifier == bundle.bundleIdentifier })?.resignedBundleIdentifier
                
                if let resignedID,
                   let customEntitlements = self.context.installedApp?.customEntitlements(forResignedID: resignedID) {
                    self.context.customEntitlementsByBundleID[bundle.bundleIdentifier] = customEntitlements
                }
            }

            // 2. Apply custom Info.plist if available
            if let customPlist = self.context.customInfoPlistByBundleID[bundle.bundleIdentifier] {
                do {
                    if isMain {
                        let customParser = InfoPlistParser(dictionary: customPlist)
                        if let customID = customParser.bundleIdentifier,
                           !customID.isEmpty,
                           customID != self.context.bundleIdentifier {
                            self.context.customBundleIdentifier = customID
                        }
                    }
                    
                    try bundle.updateInfoPlist(with: customPlist)
                    debugLog("[PatchInfoPlistOperation] Successfully patched Info.plist for \(bundle.bundleIdentifier)")
                } catch {
                    debugLog("[PatchInfoPlistOperation] Error applying custom Info.plist for \(bundle.bundleIdentifier): \(error)")
                    throw error
                }
            }

            // 3. Register custom entitlements if available
            if let customEntitlements = self.context.customEntitlementsByBundleID[bundle.bundleIdentifier] {
                if isMain {
                    for (key, value) in customEntitlements {
                        self.context.additionalEntitlements[ALTEntitlement(key)] = value
                    }
                }
                debugLog("[PatchInfoPlistOperation] Successfully loaded custom entitlements for \(bundle.bundleIdentifier)")
            }
        }
    }
}
