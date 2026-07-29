//
//  FetchProvisioningProfilesOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import AltStoreCore
import AltSign
import CoreData


@objc(FetchProvisioningProfilesOperation)
class FetchProvisioningProfilesOperation: ResultOperation<[String: ALTProvisioningProfile]>, OperationLogging {

    let context: AppOperationContext
    
    var additionalEntitlements: [ALTEntitlement: Any]?
    
    // this class is abstract or shouldn't be instantiated outside, use the subclasses
    fileprivate init(context: AppOperationContext) {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main() {
        super.main()
        
        Task {
            do {
                let profiles = try await self.execute()
                self.finish(.success(profiles))
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    private nonisolated func execute() async throws -> [String: ALTProvisioningProfile] {
        if let error = self.context.error {
            self.debugLog("[FetchProvisioningProfiles] Context has pre-existing error: \(error.localizedDescription)")
            throw error
        }
        
        guard let team = self.context.team,
              let session = self.context.session else {
            self.debugLog("[FetchProvisioningProfiles] Missing parameters: team=\(String(describing: self.context.team)), session=\(String(describing: self.context.session))")
            throw OperationError.invalidParameters("FetchProvisioningProfilesOperation.main: self.context.team or self.context.session is nil")
        }
        
        guard let app = self.context.app else {
            self.debugLog("[FetchProvisioningProfiles] App not found in context.")
            throw OperationError.appNotFound(name: nil)
        }
        
        let effectiveBundleId = self.context.targetBundleIdentifier
        self.debugLog("[FetchProvisioningProfiles] Executing for app \(app.name) (\(app.bundleIdentifier)), targetBundleID: \(effectiveBundleId), team: \(team.identifier) (\(team.name)), useMainProfile: \(self.context.useMainProfile)")
        
        self.progress.totalUnitCount = Int64(1 + app.appExtensions.count)

        self.debugLog("[FetchProvisioningProfiles] Preparing main provisioning profile for \(app.bundleIdentifier)...")
        let profile = try await self.prepareProvisioningProfile(for: app, parentApp: nil, team: team, session: session)
        self.debugLog("[FetchProvisioningProfiles] Main profile prepared successfully for \(effectiveBundleId), expiration: \(String(describing: profile.expirationDate))")
        self.progress.completedUnitCount += 1
        
        var profiles = [effectiveBundleId: profile]
        
        if !self.context.useMainProfile {
            self.debugLog("[FetchProvisioningProfiles] Preparing profiles for \(app.appExtensions.count) app extensions...")
            try await withThrowingTaskGroup(of: (String, ALTProvisioningProfile).self) { group in
                for appExtension in app.appExtensions {
                    group.addTask {
                        self.verboseLog("[FetchProvisioningProfiles] Preparing extension profile for \(appExtension.bundleIdentifier)...")
                        let extProfile = try await self.prepareProvisioningProfile(for: appExtension, parentApp: app, team: team, session: session)
                        // Use customized bundle ID if applicable
                        let updatedExtensionBundleId = appExtension.bundleIdentifier.replacingOccurrences(of: app.bundleIdentifier, with: effectiveBundleId)
                        self.verboseLog("[FetchProvisioningProfiles] Extension profile prepared for \(updatedExtensionBundleId)")
                        return (updatedExtensionBundleId, extProfile)
                    }
                }
                
                for try await (bundleId, extProfile) in group {
                    profiles[bundleId] = extProfile
                    self.debugLog("[FetchProvisioningProfiles] Added profile for extension bundle ID: \(bundleId)")
                    self.progress.completedUnitCount += 1
                }
            }
        }
        
        self.debugLog("[FetchProvisioningProfiles] Total profiles prepared: \(profiles.count) -> keys: \(Array(profiles.keys))")
        return profiles
    }
    
    func process<T>(_ result: Result<T, Error>) -> T? {
        switch result {
        case .failure(let error):
            self.finish(.failure(error))
            return nil
            
        case .success(let value):
            guard !self.isCancelled else {
                self.finish(.failure(OperationError.cancelled))
                return nil
            }
            
            return value
        }
    }
    
    internal func fetchProvisioningProfile(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        debugLog(app.dumpMachOInfo())
        debugLog("[FetchProvisioningProfiles] Fetching existing provisioning profile to get its identifier for App ID \(appID.bundleIdentifier).")
        let profile = try await ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, deviceType: .iphone, team: team, session: session)
        
        do {
            // Delete existing profile
            debugLog("[FetchProvisioningProfiles] Deleting existing provisioning profile \(profile.identifier ?? "unknown") (\(profile.name)) from Apple's servers.")
            try await ALTAppleAPI.shared.deleteProvisioningProfile(profile, for: team, session: session)
            
            debugLog("[FetchProvisioningProfiles] Generating new free provisioning profile for App ID \(appID.bundleIdentifier) by fetching again.")
            
            // Fetch new provisioning profile
            return try await ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, deviceType: .iphone, team: team, session: session)
        } catch {
            // As of March 20, 2023, the free provisioning profile is re-generated each fetch, and you can no longer delete it.
            // So instead, we just return the fetched profile from above.
            if team.type == .free {
                debugLog("[FetchProvisioningProfiles] Delete failed as expected for free provisioning account (deletion is blocked post-March 2023). Returning the freshly generated profile from the first fetch.")
            } else {
                debugLog("[FetchProvisioningProfiles] Delete failed for paid developer account: \(error.localizedDescription). Returning the profile fetched initially.")
            }
            return profile
        }
    }
    
    private func fetchPreferredBundleID(for app: ALTApplication, team: ALTTeam) async throws -> String? {
        await DatabaseManager.shared.persistentContainer.performBackgroundTask { [weak self] (context) -> String? in
            guard let self else { return nil }
            return preferredBundleID(for: app, team: team, in: context)
        }
    }
    
    private func preferredBundleID(for app: ALTApplication, team: ALTTeam, in context: NSManagedObjectContext) -> String? {
        // Check if we have already installed this app with this team before.
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
        guard let installedApp = InstalledApp.first(satisfying: predicate, in: context) else {
            self.verboseLog("[FetchProvisioningProfiles] No existing InstalledApp found for bundleID: \(app.bundleIdentifier)")
            return nil
        }
        
        // Teams match if installedApp.team has same identifier as team (or team is nil)
        // AND installedApp.resignedBundleIdentifier actually contains the team's identifier.
        let teamsMatch = (installedApp.team?.identifier == team.identifier || installedApp.team == nil)
                         && installedApp.resignedBundleIdentifier.contains(team.identifier)
        
        self.verboseLog("[FetchProvisioningProfiles] preferredBundleID check: app=\(app.bundleIdentifier), installedResignedID=\(installedApp.resignedBundleIdentifier), installedTeam=\(installedApp.team?.identifier ?? "nil"), targetTeam=\(team.identifier), teamsMatch=\(teamsMatch)")

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
    
    private func prepareProvisioningProfile(for app: ALTApplication,
                                    parentApp: ALTApplication?,
                                    team: ALTTeam,
                                    session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        let preferredBundleID = try await self.fetchPreferredBundleID(for: app, team: team)
        
        let bundleID: String
        
        if let preferredBundleID = preferredBundleID {
            bundleID = preferredBundleID
            self.debugLog("[FetchProvisioningProfiles] Using preferredBundleID: \(bundleID)")
        } else {
            let parentBundleID = parentApp?.bundleIdentifier ?? app.bundleIdentifier
            let effectiveParentBundleID = self.context.targetBundleIdentifier
            let updatedParentBundleID = effectiveParentBundleID + "." + team.identifier

            if let parentApp = parentApp,
               app.bundleIdentifier.hasPrefix(parentBundleID + ".") {
                let suffix = String(app.bundleIdentifier.dropFirst(parentBundleID.count))
                bundleID = updatedParentBundleID + suffix
            } else {
                bundleID = updatedParentBundleID
            }
            self.debugLog("[FetchProvisioningProfiles] Constructed mangled bundleID: \(bundleID) (effectiveParent: \(effectiveParentBundleID), team: \(team.identifier))")
        }
        
        let preferredName: String
        
        if let parentApp = parentApp {
            preferredName = parentApp.name + " " + app.name
        } else {
            preferredName = app.name
        }
        
        self.debugLog("[FetchProvisioningProfiles] Registering App ID with name '\(preferredName)' and bundleID '\(bundleID)'...")
        // Register
        let appID = try await self.registerAppID(for: app, name: preferredName, bundleIdentifier: bundleID, team: team, session: session)
        self.debugLog("[FetchProvisioningProfiles] App ID registered successfully: \(appID.bundleIdentifier) (\(appID.identifier))")
        
        // Fetch Provisioning Profile
        self.debugLog("[FetchProvisioningProfiles] Fetching provisioning profile for App ID \(appID.bundleIdentifier)...")
        let profile = try await self.fetchProvisioningProfile(for: appID, app: app, team: team, session: session)
        self.debugLog("[FetchProvisioningProfiles] Provisioning profile fetched for \(appID.bundleIdentifier) (Name: \(profile.name), Expiration: \(String(describing: profile.expirationDate)))")
        return profile
    }
    
    private func registerAppID(for application: ALTApplication,
                               name: String,
                               bundleIdentifier: String,
                               team: ALTTeam,
                               session: ALTAppleAPISession) async throws -> ALTAppID {
        self.debugLog("[FetchProvisioningProfiles] Fetching existing App IDs from Apple for team \(team.identifier)...")
        let appIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
        self.verboseLog("[FetchProvisioningProfiles] Found \(appIDs.count) existing App IDs on portal for team \(team.identifier): \(appIDs.map { $0.bundleIdentifier })")
        
        if let appID = appIDs.first(where: { $0.bundleIdentifier.lowercased() == bundleIdentifier.lowercased() }) {
            self.debugLog("[FetchProvisioningProfiles] Found existing App ID on portal: \(appID.bundleIdentifier)")
            return appID
        } else {
            let requiredAppIDs = 1 + application.appExtensions.count
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
                self.debugLog("[FetchProvisioningProfiles] Successfully registered new App ID '\(appID.bundleIdentifier)' on Apple portal.")
                return appID
            } catch ALTAppleAPIError.maximumAppIDLimitReached {
                self.debugLog("[FetchProvisioningProfiles] addAppID failed: maximumAppIDLimitReached")
                if let expirationDate = sortedExpirationDates.first {
                    throw OperationError.maximumAppIDLimitReached(appName: application.name, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, expirationDate: expirationDate)
                } else {
                    throw ALTAppleAPIError(.maximumAppIDLimitReached)
                }
            } catch ALTAppleAPIError.bundleIdentifierUnavailable {
                self.debugLog("[FetchProvisioningProfiles] addAppID failed: bundleIdentifierUnavailable for '\(bundleIdentifier)'. Re-checking portal...")
                let appIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
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
    override init(context: AppOperationContext) {
        super.init(context: context)
    }
    
    // modify Operations are allowed for the app groups and other stuffs
    override func fetchProvisioningProfile(for appID: ALTAppID,
                                    app: ALTApplication,
                                    team: ALTTeam,
                                    session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        self.debugLog("[FetchProvisioningProfilesInstall] Updating features for App ID \(appID.bundleIdentifier)...")
        let updatedAppID = try await self.updateFeatures(for: appID, app: app, team: team, session: session)
        
        self.debugLog("[FetchProvisioningProfilesInstall] Updating app groups for App ID \(updatedAppID.bundleIdentifier)...")
        let groupAppID = try await self.updateAppGroups(for: updatedAppID, app: app, team: team, session: session)
        
        self.debugLog("[FetchProvisioningProfilesInstall] Fetching profile from Apple for App ID \(groupAppID.bundleIdentifier)...")
        return try await super.fetchProvisioningProfile(for: groupAppID, app: app, team: team, session: session)
    }
    
    private func updateFeatures(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        var entitlements = app.entitlements
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
    
    private func updateAppGroups(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        var entitlements = app.entitlements
        for (key, value) in additionalEntitlements ?? [:] {
            entitlements[key] = value
        }
                
        guard var applicationGroups = entitlements[.appGroups] as? [String], !applicationGroups.isEmpty else {
            verboseLog("[FetchProvisioningProfiles] App ID \(appID.bundleIdentifier) has no app groups, skipping assignment.")
            // Assigning an App ID to an empty app group array fails,
            // so just do nothing if there are no app groups.
            return appID
        }
        
        if app.isAltStoreApp {
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
        
        return try await TaskChainSerializer.shared.serialize {
            // Ensure we're not concurrently fetching and updating app groups,
            // which can lead to race conditions such as adding an app group twice.
            do {
                let fetchedGroups = try await ALTAppleAPI.shared.fetchAppGroups(for: team, session: session)
                
                var groups = [ALTAppGroup]()
                
                for groupIdentifier in applicationGroups {
                    let adjustedGroupIdentifier = groupIdentifier + "." + team.identifier
                    
                    if let group = fetchedGroups.first(where: { $0.groupIdentifier == adjustedGroupIdentifier }) {
                        groups.append(group)
                    } else {
                        // Not all characters are allowed in group names, so we replace periods with spaces (like Apple does).
                        let name = "AltStore " + groupIdentifier.replacingOccurrences(of: ".", with: " ")
                        do {
                            let group = try await ALTAppleAPI.shared.addAppGroup(withName: name, groupIdentifier: adjustedGroupIdentifier, team: team, session: session)
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
                self.verboseLog("[FetchProvisioningProfiles] Assigned App ID \(appID.bundleIdentifier) to App Groups \(groupIDs.description).")
                
                return appID
            } catch {
                let groupIDs = applicationGroups.map { $0 + "." + team.identifier }
                self.debugLog("[FetchProvisioningProfiles] Failed to assign/create App Groups for App ID \(appID.bundleIdentifier): \(error.localizedDescription)")
                throw error
            }
        }
    }
}

// <TEST> : users were reporting that refresh (though seemed like it refreshed the app becomes no longer available)
//          possibly, this is caused since refesh was not updating appFeatures and AppGroups in the new profile? not sure.
//          for now we are reverting by keeping same operation that happens during fetch in install path to see if it fixes issue #893
// class FetchProvisioningProfilesRefreshOperation: FetchProvisioningProfilesOperation, @unchecked Sendable {
class FetchProvisioningProfilesRefreshOperation: FetchProvisioningProfilesInstallOperation, @unchecked Sendable {
    override init(context: AppOperationContext) {
        super.init(context: context)
    }
}


