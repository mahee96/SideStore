//
//  CacheProvisioningProfilesOperation.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

final class CacheProvisioningProfilesOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[CacheProvisioningProfilesOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[CacheProvisioningProfilesOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        let bundleID = self.context.targetBundleIdentifier
        if bundleID.isAltStoreAppID {
            debugLog("[CacheProvisioningProfilesOperation] Skipping caching of profiles for self (\(bundleID)).")
            return
        }
        
        guard let profiles = self.context.provisioningProfiles, !profiles.isEmpty else {
            debugLog("[CacheProvisioningProfilesOperation] No provisioning profiles to cache.")
            return
        }
        
        let profilesDirectory = InstalledApp.customProvisioningProfilesDirectoryURL(forBundleIdentifier: bundleID)
        try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true, attributes: nil)
        
        for (targetID, profile) in profiles {
            let fileURL = profilesDirectory.appendingPathComponent("\(targetID).mobileprovision")
            try profile.data.write(to: fileURL, options: .atomic)
            debugLog("[CacheProvisioningProfilesOperation] Cached provisioning profile for \(targetID) to \(fileURL.path)")
        }
        
        // Also save main profile as embedded.mobileprovision in the app's cache directory
        if let mainProfile = self.context.useMainProfile ? profiles.values.first : profiles[bundleID] {
            let mainURL = InstalledApp.appsDirectoryURL.appendingPathComponent(bundleID).appendingPathComponent("embedded.mobileprovision")
            try? mainProfile.data.write(to: mainURL, options: .atomic)
        }
        
        self.setProgress(100)
    }
}
