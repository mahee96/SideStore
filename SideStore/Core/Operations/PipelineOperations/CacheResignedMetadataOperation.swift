//
//  CacheResignedMetadataOperation.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

final class CacheResignedMetadataOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[CacheResignedMetadataOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[CacheResignedMetadataOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        let bundleID = self.context.targetBundleIdentifier
        if bundleID.isAltStoreAppID {
            debugLog("[CacheResignedMetadataOperation] Skipping caching of resigned metadata for self (\(bundleID)).")
            return
        }
        
        // 1. Cache Provisioning Profiles
        if let profiles = self.context.provisioningProfiles, !profiles.isEmpty {
            let profilesDirectory = InstalledApp.customProvisioningProfilesDirectoryURL(forBundleIdentifier: bundleID)
            try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true, attributes: nil)
            
            for (_, profile) in profiles {
                let targetID = profile.bundleIdentifier
                let fileURL = profilesDirectory.appendingPathComponent("\(targetID).mobileprovision")
                try profile.data.write(to: fileURL, options: .atomic)
                debugLog("[CacheResignedMetadataOperation] Cached provisioning profile for \(targetID) to \(fileURL.path)")
            }
            
            // Also write main profile as embedded.mobileprovision in the app's cache directory
            if let mainProfile = self.context.useMainProfile ? profiles.values.first : (profiles[bundleID] ?? profiles.values.first) {
                let mainURL = InstalledApp.appsDirectoryURL.appendingPathComponent(bundleID).appendingPathComponent("embedded.mobileprovision")
                try? mainProfile.data.write(to: mainURL, options: .atomic)
            }
        }
        
        // 2. Cache Info.plist (cached for all targets from resigned bundles or customizations)
        let infoPlistDirectory = InstalledApp.customInfoPlistDirectoryURL(forBundleIdentifier: bundleID)
        try FileManager.default.createDirectory(at: infoPlistDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let targetAppBundle = self.context.resignedAppBundle ?? self.context.targetAppBundle
        if let targetAppBundle {
            for bundle in targetAppBundle.allAppBundles {
                let targetID = bundle.bundleIdentifier
                let destURL = infoPlistDirectory.appendingPathComponent("\(targetID).plist")
                do {
                    let parser = try InfoPlistParser(bundleURL: bundle.fileURL)
                    try parser.write(to: destURL)
                    debugLog("[CacheResignedMetadataOperation] Cached resigned Info.plist for \(targetID) to \(destURL.path)")
                    
                    if bundle == targetAppBundle {
                        let legacyURL = InstalledApp.appsDirectoryURL.appendingPathComponent(bundleID).appendingPathComponent("custom_info.plist")
                        try? parser.write(to: legacyURL)
                    }
                } catch {
                    debugLog("[CacheResignedMetadataOperation] Failed to cache Info.plist for \(targetID) from \(bundle.fileURL.path): \(error)")
                }
            }
        } else if !self.context.customInfoPlistByBundleID.isEmpty {
            for (targetID, plist) in self.context.customInfoPlistByBundleID {
                let effectiveTargetID = (targetID == bundleID) ? (targetAppBundle?.bundleIdentifier ?? targetID) : targetID
                let destURL = infoPlistDirectory.appendingPathComponent("\(effectiveTargetID).plist")
                try InfoPlistParser(dictionary: plist).write(to: destURL)
                debugLog("[CacheResignedMetadataOperation] Cached custom Info.plist for \(effectiveTargetID) to \(destURL.path)")
                if targetID == bundleID {
                    let legacyURL = InstalledApp.appsDirectoryURL.appendingPathComponent(bundleID).appendingPathComponent("custom_info.plist")
                    try? InfoPlistParser(dictionary: plist).write(to: legacyURL)
                }
            }
        }
        
        // 3. Cache Entitlements
        let entitlementsDirectory = InstalledApp.customEntitlementsDirectoryURL(forBundleIdentifier: bundleID)
        try FileManager.default.createDirectory(at: entitlementsDirectory, withIntermediateDirectories: true, attributes: nil)
        
        for (targetID, entitlements) in self.context.customEntitlementsByBundleID {
            let effectiveTargetID = (targetID == bundleID) ? (targetAppBundle?.bundleIdentifier ?? targetID) : targetID
            let fileURL = entitlementsDirectory.appendingPathComponent("\(effectiveTargetID).plist")
            let plistData = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
            try plistData.write(to: fileURL, options: .atomic)
            debugLog("[CacheResignedMetadataOperation] Cached custom Entitlements for \(effectiveTargetID) to \(fileURL.path)")
        }
        
        if let profiles = self.context.provisioningProfiles {
            for (_, profile) in profiles {
                let targetID = profile.bundleIdentifier
                let fileURL = entitlementsDirectory.appendingPathComponent("\(targetID).plist")
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    if let plistData = try? PropertyListSerialization.data(fromPropertyList: profile.entitlements, format: .xml, options: 0) {
                        try? plistData.write(to: fileURL, options: .atomic)
                        debugLog("[CacheResignedMetadataOperation] Cached profile Entitlements for \(targetID) to \(fileURL.path)")
                    }
                }
            }
        }
        
        self.setProgress(100)
    }
}
