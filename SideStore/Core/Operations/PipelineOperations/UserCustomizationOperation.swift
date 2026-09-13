//
//  UserCustomizationOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//


import Foundation
import CoreData
import SideSign

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

        if context.isStoreUpdate {
            debugLog("[UserCustomizationOperation] Store app update button clicked; skipping customization modal.")
            self.setProgress(100)
            return nil
        }

        let handler = context.handler.userCustomizationHandler

        if UserDefaults.standard.customizeInfoPlist {
            let authoritativeBundleID = context.installedApp?.bundleIdentifier ?? context.targetBundleIdentifier
            let appDirectory = InstalledApp.appsDirectoryURL.appendingPathComponent(authoritativeBundleID)
            let cachedPlistURL = appDirectory.appendingPathComponent("custom_info.plist")
            
            var cachedPlist: [String: any Sendable]? = nil
            if FileManager.default.fileExists(atPath: cachedPlistURL.path),
               let parser = try? InfoPlistParser(plistURL: cachedPlistURL) {
                cachedPlist = parser.rawDictionary
                debugLog("[UserCustomizationOperation] Primed custom Info.plist from \(cachedPlistURL.path)")
            }

            let initialPlist: [String: any Sendable] = {
                if let cached = cachedPlist {
                    return cached
                }
                if let targetAppBundle = context.targetAppBundle {
                    return targetAppBundle.infoPlist
                }
                return ["CFBundleIdentifier": context.targetBundleIdentifier]
            }()

            let initialBundleID = (cachedPlist?["CFBundleIdentifier"] as? String) ?? context.targetBundleIdentifier
            let installedAppTeamID = context.installedApp?.team?.identifier
            let authTeam = try await AuthManager.shared.getAuthenticatedTeam()
            let teamID = authTeam.identifier
            debugLog("[UserCustomizationOperation] initialBundleID='\(initialBundleID)', installedAppTeamID='\(installedAppTeamID ?? "nil")', authTeamID='\(teamID)', appendTeamID=\(context.appendTeamID)")
            guard !teamID.isEmpty else {
                debugLog("[UserCustomizationOperation] FAILED: authTeamID is empty")
                throw OperationError.invalidParameters("Active developer team identifier is missing.")
            }
            debugLog("[UserCustomizationOperation] resolved teamID='\(teamID)'")

            // Fetch installed apps to detect existing installations by authoritative bundle ID
            let installedApps: [InstalledApp] = context.dbBackgroundContext.performAndWait {
                let request = InstalledApp.fetchRequest()
                return (try? context.dbBackgroundContext.fetch(request)) ?? []
            }
            let installedAppIdentities = Dictionary(
                installedApps.compactMap { app -> (String, String)? in
                    (app.bundleIdentifier, app.name)
                },
                uniquingKeysWith: { first, _ in first }
            )

            self.setProgress(40)

            guard let result = try await handler.resolveInfoPlistCustomization(
                initialPlist: initialPlist,
                initialBundleID: initialBundleID,
                appendTeamID: context.appendTeamID,
                installedAppIdentities: installedAppIdentities,
                teamID: teamID
            ) else {
                throw OperationError.cancelled
            }

            context.appendTeamID = result.appendTeamID

            let customID = (result.modifiedPlist["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let customID = customID, !customID.isEmpty, customID != context.bundleIdentifier {
                context.customBundleIdentifier = customID
            } else {
                context.customBundleIdentifier = nil
            }

            context.customInfoPlistByBundleID[context.targetBundleIdentifier] = result.modifiedPlist

            // Dynamically link existing installed app if bundle ID matches
            let effectiveCustomID = customID ?? initialBundleID
            let resolvedID = result.appendTeamID && !teamID.isEmpty ? "\(effectiveCustomID).\(teamID)" : effectiveCustomID
            if let matchingApp = installedApps.first(where: { $0.bundleIdentifier == resolvedID }) {
                debugLog("[UserCustomizationOperation] Matched existing installed app: \(matchingApp.name) (\(resolvedID))")
                context.installedApp = matchingApp
            } else {
                debugLog("[UserCustomizationOperation] No matching installed app for \(resolvedID); treating as new install/clone.")
                context.installedApp = nil
            }

            if let targetAppBundle = context.targetAppBundle {
                try? targetAppBundle.updateInfoPlist(with: result.modifiedPlist)
            }
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
        }

        if UserDefaults.standard.customizeEntitlements {
            let authTeam = try await AuthManager.shared.getAuthenticatedTeam()
            let initialEntitlements = context.targetAppBundle?.entitlements ?? [:]
            self.setProgress(70)

            guard let result = try await handler.resolveEntitlementsCustomization(
                initialEntitlements: initialEntitlements,
                bundleID: context.targetBundleIdentifier,
                teamType: authTeam.type
            ) else {
                throw OperationError.cancelled
            }

            context.customEntitlementsByBundleID[context.targetBundleIdentifier] = result
            for (key, value) in result {
                context.additionalEntitlements[ALTEntitlement(key)] = value
            }
        }

        self.setProgress(100)
        if UserDefaults.standard.customizeInfoPlist || UserDefaults.standard.customizeAppId {
            return context.targetBundleIdentifier
        } else {
            return nil
        }
    }
}
