//
//  CacheUserCustomizationsOperation.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

final class CacheUserCustomizationsOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[CacheUserCustomizationsOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[CacheUserCustomizationsOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        let bundleID = self.context.targetBundleIdentifier
        if bundleID.isAltStoreAppID {
            debugLog("[CacheUserCustomizationsOperation] Skipping caching of customizations for self (\(bundleID)).")
            return
        }
        
        // Cache Info.plist customizations
        let customInfoPlists = self.context.customInfoPlistByBundleID
        if !customInfoPlists.isEmpty {
            let infoPlistDirectory = InstalledApp.customInfoPlistDirectoryURL(forBundleIdentifier: bundleID)
            try FileManager.default.createDirectory(at: infoPlistDirectory, withIntermediateDirectories: true, attributes: nil)
            for (targetID, plist) in customInfoPlists {
                let fileURL = infoPlistDirectory.appendingPathComponent("\(targetID).plist")
                try InfoPlistParser(dictionary: plist).write(to: fileURL)
                debugLog("[CacheUserCustomizationsOperation] Cached Info.plist for \(targetID) to \(fileURL.path)")
            }
            // Also write legacy custom_info.plist for main app compatibility
            if let mainPlist = customInfoPlists[bundleID] {
                let legacyURL = InstalledApp.appsDirectoryURL.appendingPathComponent(bundleID).appendingPathComponent("custom_info.plist")
                try? InfoPlistParser(dictionary: mainPlist).write(to: legacyURL)
            }
        }
        
        // Cache Entitlements customizations
        let customEntitlements = self.context.customEntitlementsByBundleID
        if !customEntitlements.isEmpty {
            let entitlementsDirectory = InstalledApp.customEntitlementsDirectoryURL(forBundleIdentifier: bundleID)
            try FileManager.default.createDirectory(at: entitlementsDirectory, withIntermediateDirectories: true, attributes: nil)
            for (targetID, entitlements) in customEntitlements {
                let fileURL = entitlementsDirectory.appendingPathComponent("\(targetID).plist")
                let plistData = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
                try plistData.write(to: fileURL, options: .atomic)
                debugLog("[CacheUserCustomizationsOperation] Cached Entitlements for \(targetID) to \(fileURL.path)")
            }
        }
        
        self.setProgress(100)
    }
}
