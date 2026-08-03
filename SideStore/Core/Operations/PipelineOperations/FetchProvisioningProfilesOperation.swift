//
//  FetchProvisioningProfilesOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign
import CoreData

class FetchProvisioningProfilesOperation: BasePipelineOperation<AppOperationContext, [String: ALTProvisioningProfile]>, @unchecked Sendable {
    var additionalEntitlements: [ALTEntitlement: Any]?
    
    // this class is abstract or shouldn't be instantiated outside, use the subclasses
    
    override func execute(parentProgress: Progress?) async throws -> [String: ALTProvisioningProfile] {
        debugLog("[FetchProvisioningProfilesOperation] execute() started")
        defer { debugLog("[FetchProvisioningProfilesOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        if let error = self.context.error {
            self.debugLog("[FetchProvisioningProfiles] Context has pre-existing error: \(error.localizedDescription)")
            throw error
        }
        
        guard let team = self.context.authenticatedContext.team,
              let session = self.context.authenticatedContext.session else {
            self.debugLog("[FetchProvisioningProfiles] Missing parameters: team=\(String(describing: self.context.authenticatedContext.team)), session=\(String(describing: self.context.authenticatedContext.session))")
            throw OperationError.invalidParameters("FetchProvisioningProfilesOperation.main: self.context.authenticatedContext.team or self.context.authenticatedContext.session is nil")
        }
        
        guard let appBundle = self.context.appBundle else {
            self.debugLog("[FetchProvisioningProfiles] App not found in context.")
            throw OperationError.appNotFound(name: nil)
        }
        
        let effectiveBundleId = self.context.targetBundleIdentifier
        self.debugLog("[FetchProvisioningProfiles] Executing for app \(appBundle.bundleIdentifier), targetBundleID: \(effectiveBundleId), team: \(team.identifier), useMainProfile: \(self.context.useMainProfile)")
        
        self.setProgress(10)

        self.debugLog("[FetchProvisioningProfiles] Preparing main provisioning profile for \(appBundle.bundleIdentifier)...")
        let profile = try await self.prepareProvisioningProfile(for: appBundle, parentAppBundle: nil, team: team, session: session)
        self.debugLog("[FetchProvisioningProfiles] Main profile prepared successfully for \(effectiveBundleId), expiration: \(String(describing: profile.expirationDate))")
        
        var profiles = [effectiveBundleId: profile]
        
        if !self.context.useMainProfile && !appBundle.appExtensions.isEmpty {
            self.setProgress(50)
            self.debugLog("[FetchProvisioningProfiles] Preparing profiles for \(appBundle.appExtensions.count) app extensions...")
            try await withThrowingTaskGroup(of: (String, ALTProvisioningProfile).self) { group in
                for appExtension in appBundle.appExtensions {
                    group.addTask {
                        self.verboseLog("[FetchProvisioningProfiles] Preparing extension profile for \(appExtension.bundleIdentifier)...")
                        let extProfile = try await self.prepareProvisioningProfile(for: appExtension, parentAppBundle: appBundle, team: team, session: session)
                        // Use customized bundle ID if applicable
                        let updatedExtensionBundleId = appExtension.bundleIdentifier.replacingOccurrences(of: appBundle.bundleIdentifier, with: effectiveBundleId)
                        self.verboseLog("[FetchProvisioningProfiles] Extension profile prepared for \(updatedExtensionBundleId)")
                        return (updatedExtensionBundleId, extProfile)
                    }
                }
                
                var completedCount = 0
                let totalExtensions = appBundle.appExtensions.count
                let startProgress = self.progress.completedUnitCount
                let endProgress: Int64 = 100
                let range = endProgress - startProgress
                
                for try await (bundleId, extProfile) in group {
                    profiles[bundleId] = extProfile
                    self.debugLog("[FetchProvisioningProfiles] Added profile for extension bundle ID: \(bundleId)")
                    completedCount += 1
                    if range > 0 {
                        let percent = startProgress + Int64(Double(completedCount) / Double(totalExtensions) * Double(range))
                        self.setProgress(percent)
                    }
                }
            }
        } else {
            self.setProgress(100)
        }
        
        self.debugLog("[FetchProvisioningProfiles] Total profiles prepared: \(profiles.count) -> keys: \(Array(profiles.keys))")
        return profiles
    }

    
    internal func fetchProvisioningProfile(for appID: ALTAppID, appBundle: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        verboseLog(appBundle.dumpMachOInfo())
        debugLog("[FetchProvisioningProfiles] Fetching existing provisioning profile to get its identifier for App ID \(appID.bundleIdentifier).")
        let profile = try await ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, deviceType: .iphone, team: team, session: session)
        return profile
    }
    
    private func fetchPreferredBundleID(for appBundle: ALTApplication, team: ALTTeam) async throws -> String? {
        await DatabaseManager.shared.persistentContainer.performBackgroundTask { [weak self] (context) -> String? in
            guard let self else { return nil }
            return preferredBundleID(for: appBundle, team: team, in: context)
        }
    }
    
    private func preferredBundleID(for appBundle: ALTApplication, team: ALTTeam, in context: NSManagedObjectContext) -> String? {
        // Check if we have already installed this app with this team before.
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), appBundle.bundleIdentifier)
        guard let installedApp = InstalledApp.first(satisfying: predicate, in: context) else {
            self.verboseLog("[FetchProvisioningProfiles] No existing InstalledApp found for bundleID: \(appBundle.bundleIdentifier)")
            return nil
        }
        
        // Teams match if installedApp.team has same identifier as team (or team is nil)
        // AND installedApp.resignedBundleIdentifier actually contains the team's identifier.
        let teamsMatch = (installedApp.team?.identifier == team.identifier || installedApp.team == nil)
                         && installedApp.resignedBundleIdentifier.contains(team.identifier)
        
        self.verboseLog("[FetchProvisioningProfiles] preferredBundleID check: app=\(appBundle.bundleIdentifier), installedResignedID=\(installedApp.resignedBundleIdentifier), installedTeam=\(installedApp.team?.identifier ?? "nil"), targetTeam=\(team.identifier), teamsMatch=\(teamsMatch)")

        // TODO: @mahee96: Try to keep the debug build and release build operations similar, refactor later with proper reasoning
        //                 for now, restricted it to debug on simulator only
        #if DEBUG && targetEnvironment(simulator)

        let result = teamsMatch ? installedApp.resignedBundleIdentifier : nil
        self.debugLog("[FetchProvisioningProfiles] preferredBundleID result (DEBUG simulator): \(result ?? "nil")")
        return result

        #else
        
        let result = teamsMatch ? installedApp.resignedBundleIdentifier : nil
        self.debugLog("[FetchProvisioningProfiles] preferredBundleID result: \(result ?? "nil")")
        return result
        
        #endif
    }
    
    private func prepareProvisioningProfile(for appBundle: ALTApplication,
                                    parentAppBundle: ALTApplication?,
                                    team: ALTTeam,
                                    session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        let preferredBundleID = try await self.fetchPreferredBundleID(for: appBundle, team: team)
        
        let bundleID: String
        
        if let preferredBundleID = preferredBundleID {
            bundleID = preferredBundleID
            self.debugLog("[FetchProvisioningProfiles] Using preferredBundleID: \(bundleID)")
        } else {
            let parentBundleID = parentAppBundle?.bundleIdentifier ?? appBundle.bundleIdentifier
            let effectiveParentBundleID = self.context.targetBundleIdentifier
            let updatedParentBundleID = effectiveParentBundleID + "." + team.identifier

            if let parentAppBundle = parentAppBundle,
               appBundle.bundleIdentifier.hasPrefix(parentBundleID + ".") {
                let suffix = String(appBundle.bundleIdentifier.dropFirst(parentBundleID.count))
                bundleID = updatedParentBundleID + suffix
            } else {
                bundleID = updatedParentBundleID
            }
            self.debugLog("[FetchProvisioningProfiles] Constructed mangled bundleID: \(bundleID) (effectiveParent: \(effectiveParentBundleID), team: \(team.identifier))")
        }
        
        let preferredName: String
        
        if let parentAppBundle = parentAppBundle {
            preferredName = parentAppBundle.name + " " + appBundle.name
        } else {
            preferredName = appBundle.name
        }
        
        self.debugLog("[FetchProvisioningProfiles] Registering App ID with name '\(preferredName)' and bundleID '\(bundleID)'...")
        // Register
        let appID = try await self.registerAppID(for: appBundle, name: preferredName, bundleIdentifier: bundleID, team: team, session: session)
        self.debugLog("[FetchProvisioningProfiles] App ID registered successfully: \(appID.bundleIdentifier) (\(appID.identifier))")
        
        // Fetch Provisioning Profile
        self.debugLog("[FetchProvisioningProfiles] Fetching provisioning profile for App ID \(appID.bundleIdentifier)...")
        let profile = try await self.fetchProvisioningProfile(for: appID, appBundle: appBundle, team: team, session: session)
        self.debugLog("[FetchProvisioningProfiles] Provisioning profile fetched for \(appID.bundleIdentifier) (Name: \(profile.name), Expiration: \(String(describing: profile.expirationDate)))")
        return profile
    }
    
    private func registerAppID(for appBundle: ALTApplication,
                               name: String,
                               bundleIdentifier: String,
                               team: ALTTeam,
                               session: ALTAppleAPISession) async throws -> ALTAppID {
        let appIDs: [ALTAppID]
        if let cachedAppIDs = self.context.authenticatedContext.appIDs {
            self.debugLog("[FetchProvisioningProfiles] Using cached App IDs from shared context.")
            appIDs = cachedAppIDs
        } else {
            self.debugLog("[FetchProvisioningProfiles] Fetching existing App IDs from Apple for team \(team.identifier)...")
            let fetchedAppIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
            self.context.authenticatedContext.appIDs = fetchedAppIDs
            appIDs = fetchedAppIDs
            self.verboseLog("[FetchProvisioningProfiles] Found \(appIDs.count) existing App IDs on portal for team \(team.identifier): \(appIDs.map { $0.bundleIdentifier })")
        }
        
        if let appID = appIDs.first(where: { $0.bundleIdentifier.lowercased() == bundleIdentifier.lowercased() }) {
            self.debugLog("[FetchProvisioningProfiles] Found existing App ID on portal: \(appID.bundleIdentifier)")
            return appID
        } else {
            let requiredAppIDs = 1 + appBundle.appExtensions.count
            let availableAppIDs = max(0, Team.maximumFreeAppIDs - appIDs.count)
            self.verboseLog("[FetchProvisioningProfiles] App ID not found on portal for '\(bundleIdentifier)'. Required: \(requiredAppIDs), Available: \(availableAppIDs) (teamType: \(team.type))")
            
            let sortedExpirationDates = appIDs.compactMap { $0.expirationDate }.sorted(by: { $0 < $1 })
            
            //App ID name must be ascii. If the name is not ascii, using bundleID instead
            let appIDName: String
            if !name.allSatisfy({ $0.isASCII }) {
                //Contains non ASCII (Such as Chinese/Japanese...), using bundleID
                appIDName = bundleIdentifier
            } else {
                //ASCII text, keep going as usual
                appIDName = name
            }
            
            do {
                self.debugLog("[FetchProvisioningProfiles] Calling ALTAppleAPI.shared.addAppID with name '\(appIDName)' and identifier '\(bundleIdentifier)'...")
                let appID = try await ALTAppleAPI.shared.addAppID(withName: appIDName, bundleIdentifier: bundleIdentifier, team: team, session: session)
                self.context.authenticatedContext.appIDs?.append(appID)
                self.debugLog("[FetchProvisioningProfiles] Successfully registered new App ID '\(appID.bundleIdentifier)' on Apple portal.")
                return appID
            } catch ALTAppleAPIError.maximumAppIDLimitReached {
                self.debugLog("[FetchProvisioningProfiles] addAppID failed: maximumAppIDLimitReached")
                if let expirationDate = sortedExpirationDates.first {
                    throw OperationError.maximumAppIDLimitReached(appName: appBundle.name, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, expirationDate: expirationDate)
                } else {
                    throw ALTAppleAPIError(.maximumAppIDLimitReached)
                }
            } catch ALTAppleAPIError.bundleIdentifierUnavailable {
                self.debugLog("[FetchProvisioningProfiles] addAppID failed: bundleIdentifierUnavailable for '\(bundleIdentifier)'. Re-checking portal...")
                let appIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
                self.context.authenticatedContext.appIDs = appIDs
                if let appID = appIDs.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                    self.debugLog("[FetchProvisioningProfiles] Found App ID on secondary fetch after bundleIdentifierUnavailable: \(appID.bundleIdentifier)")
                    return appID
                } else {
                    self.debugLog("[FetchProvisioningProfiles] App ID '\(bundleIdentifier)' unavailable and not found in secondary fetch.")
                    throw ALTError(.unknown)
                }
            } catch {
                self.debugLog("[FetchProvisioningProfiles] addAppID failed with error: \(error.localizedDescription)")
                throw error
            }
        }
    }
}

class FetchProvisioningProfilesInstallOperation: FetchProvisioningProfilesOperation, @unchecked Sendable {
    
    // modify Operations are allowed for the app groups and other stuffs
    override func fetchProvisioningProfile(for appID: ALTAppID,
                                    appBundle: ALTApplication,
                                    team: ALTTeam,
                                    session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        self.debugLog("[FetchProvisioningProfilesInstall] Updating features for App ID \(appID.bundleIdentifier)...")
        let updatedAppID = try await self.updateFeatures(for: appID, appBundle: appBundle, team: team, session: session)
        
        self.debugLog("[FetchProvisioningProfilesInstall] Updating app groups for App ID \(updatedAppID.bundleIdentifier)...")
        let groupAppID = try await self.updateAppGroups(for: updatedAppID, appBundle: appBundle, team: team, session: session)
        
        self.debugLog("[FetchProvisioningProfilesInstall] Fetching profile from Apple for App ID \(groupAppID.bundleIdentifier)...")
        return try await super.fetchProvisioningProfile(for: groupAppID, appBundle: appBundle, team: team, session: session)
    }
    
    private func updateFeatures(for appID: ALTAppID, appBundle: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        var entitlements = appBundle.entitlements
        for (key, value) in additionalEntitlements ?? [:] {
            entitlements[key] = value
        }
        
        let requiredFeatures = entitlements.compactMap { (entitlement, value) -> (ALTFeature, Any)? in
            guard let feature = ALTFeature(entitlement: entitlement) else { return nil }
            return (feature, value)
        }
        
        var features = requiredFeatures.reduce(into: [ALTFeature: Any]()) { $0[$1.0] = $1.1 }
        
        if let applicationGroups = entitlements[.appGroups] as? [String], !applicationGroups.isEmpty {
            // App uses app groups, so assign `true` to enable the feature.
            features[.appGroups] = true
        } else {
            // App has no app groups, so assign `false` to disable the feature.
            features[.appGroups] = false
        }
        
        var updateFeatures = false
        
        // Determine whether the required features are already enabled for the AppID.
        for (feature, value) in features {
            if let appIDValue = appID.features[feature] as AnyObject?, (value as AnyObject).isEqual(appIDValue) {
                // AppID already has this feature enabled and the values are the same.
                continue
            } else if appID.features[feature] == nil, let shouldEnableFeature = value as? Bool, !shouldEnableFeature {
                // AppID doesn't already have this feature enabled, but we want it disabled anyway.
                continue
            } else {
                // AppID either doesn't have this feature enabled or the value has changed,
                // so we need to update it to reflect new values.
                updateFeatures = true
                break
            }
        }
        
        appID.entitlements = entitlements
        
        if updateFeatures || true {
            let appIDCopy = appID.copy() as! ALTAppID
            appIDCopy.features = features
            
            do {
                let updated = try await ALTAppleAPI.shared.update(appIDCopy, team: team, session: session)
                self.verboseLog("[FetchProvisioningProfiles] Updated features for App ID \(updated.bundleIdentifier).")
                return updated
            } catch {
                self.debugLog("[FetchProvisioningProfiles] Failed to update features for App ID \(appIDCopy.bundleIdentifier). \(error.localizedDescription)")
                throw error
            }
        } else {
            return appID
        }
    }
    
    private func updateAppGroups(for appID: ALTAppID, appBundle: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        var entitlements = appBundle.entitlements
        for (key, value) in additionalEntitlements ?? [:] {
            entitlements[key] = value
        }
                
        guard var applicationGroups = entitlements[.appGroups] as? [String], !applicationGroups.isEmpty else {
            verboseLog("[FetchProvisioningProfiles] App ID \(appID.bundleIdentifier) has no app groups, skipping assignment.")
            // Assigning an App ID to an empty app group array fails,
            // so just do nothing if there are no app groups.
            return appID
        }
        
        if appBundle.isAltStoreApp {
            verboseLog("[FetchProvisioningProfiles] Application groups before modifying for SideStore: \(applicationGroups)")
            
            // Remove app groups that contain AltStore since they can be problematic (cause SideStore to expire early)
            for (index, group) in applicationGroups.enumerated() {
                if group.contains("AltStore") {
                    verboseLog("[FetchProvisioningProfiles] Removing application group: \(group)")
                    applicationGroups.remove(at: index)
                }
            }
            
            // Make sure we add .AltWidget for the widget
            var altStoreAppGroupID = Bundle.baseAltStoreAppGroupID
            for (_, group) in applicationGroups.enumerated() {
                if group.contains("AltWidget") {
                    altStoreAppGroupID += ".AltWidget"
                    break
                }
            }
            
            // Potentially updating app groups for this specific AltStore.
            // Find the (unique) AltStore app group, then replace it
            // with the correct "base" app group ID.
            // Otherwise, we may append a duplicate team identifier to the end.
            if let index = applicationGroups.firstIndex(where: { $0.contains(Bundle.baseAltStoreAppGroupID) }) {
                applicationGroups[index] = altStoreAppGroupID
            } else {
                applicationGroups.append(altStoreAppGroupID)
            }
        }
        verboseLog("[FetchProvisioningProfiles] Application groups: \(applicationGroups)")
        
        do {
            let fetchedGroups: [ALTAppGroup]
            if let cachedGroups = self.context.authenticatedContext.appGroups {
                self.debugLog("[FetchProvisioningProfiles] Using cached App Groups from shared context.")
                fetchedGroups = cachedGroups
            } else {
                self.debugLog("[FetchProvisioningProfiles] Fetching existing App Groups from Apple for team \(team.identifier)...")
                let groups = try await ALTAppleAPI.shared.fetchAppGroups(for: team, session: session)
                self.context.authenticatedContext.appGroups = groups
                fetchedGroups = groups
            }
            
            var groups = [ALTAppGroup]()
            var seenGroupIDs = Set<String>()
            
            for groupIdentifier in applicationGroups {
                let adjustedGroupIdentifier = self.adjustedGroupIdentifier(for: groupIdentifier, team: team)
                guard seenGroupIDs.insert(adjustedGroupIdentifier).inserted else { continue }
                
                if let group = fetchedGroups.first(where: { $0.groupIdentifier == adjustedGroupIdentifier }) {
                    groups.append(group)
                } else {
                    // Not all characters are allowed in group names, so we replace periods with spaces (like Apple does).
                    let name = "AltStore " + groupIdentifier.replacingOccurrences(of: ".", with: " ")
                    do {
                        let group = try await ALTAppleAPI.shared.addAppGroup(withName: name, groupIdentifier: adjustedGroupIdentifier, team: team, session: session)
                        self.context.authenticatedContext.appGroups?.append(group)
                        self.verboseLog("[FetchProvisioningProfiles] Created new App Group \(group.groupIdentifier).")
                        groups.append(group)
                    } catch {
                        self.debugLog("[FetchProvisioningProfiles] Failed to create new App Group \(adjustedGroupIdentifier). \(error.localizedDescription)")
                        throw error
                    }
                }
            }
            
            try await ALTAppleAPI.shared.assign(appID, to: Array(groups), team: team, session: session)
            let groupIDs = groups.map { $0.groupIdentifier }
            self.debugLog("[FetchProvisioningProfiles] Assigned App ID \(appID.bundleIdentifier) to App Groups \(groupIDs.description).")
            
            return appID
        } catch {
            let adjustedGroupIDs = applicationGroups.map { self.adjustedGroupIdentifier(for: $0, team: team) }
            let groupIDs = Array(Set(adjustedGroupIDs))
            self.debugLog("[FetchProvisioningProfiles] Failed to assign/create App Groups for App ID \(appID.bundleIdentifier): \(error.localizedDescription)")
            throw error
        }
    }

    private func adjustedGroupIdentifier(for groupIdentifier: String, team: ALTTeam) -> String {
        // Currently Build.xconfig for debug appends suffix as TEAMID already
        #if DEBUG
        if groupIdentifier.contains(Bundle.baseAltStoreAppGroupID) && groupIdentifier.contains(team.identifier) {
            return groupIdentifier
        }
        #endif
        return groupIdentifier + "." + team.identifier
    }
}

// <TEST> : users were reporting that refresh (though seemed like it refreshed the app becomes no longer available)
//          possibly, this is caused since refesh was not updating appFeatures and AppGroups in the new profile? not sure.
//          for now we are reverting by keeping same operation that happens during fetch in install path to see if it fixes issue #893
// class FetchProvisioningProfilesRefreshOperation: FetchProvisioningProfilesOperation, @unchecked Sendable {
class FetchProvisioningProfilesRefreshOperation: FetchProvisioningProfilesInstallOperation, @unchecked Sendable {
}


