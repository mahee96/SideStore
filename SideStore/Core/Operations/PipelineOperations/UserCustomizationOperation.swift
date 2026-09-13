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
            let cacheFolderID = context.installedApp?.bundleIdentifier ?? context.bundleIdentifier
            let authTeam = try await AuthManager.shared.getAuthenticatedTeam()
            let teamID = authTeam.identifier
            debugLog("[UserCustomizationOperation] cacheFolderID='\(cacheFolderID)', authTeamID='\(teamID)', appendTeamID=\(context.appendTeamID)")
            guard !teamID.isEmpty else {
                debugLog("[UserCustomizationOperation] FAILED: authTeamID is empty")
                throw OperationError.invalidParameters("Active developer team identifier is missing.")
            }

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

            // Resolve cached plist if previously customized
            let mainCachedID = context.installedApp?.resignedBundleIdentifier ?? context.targetBundleIdentifier
            let mainCachedURL = InstalledApp.customInfoPlistURL(forBundleIdentifier: cacheFolderID, targetID: mainCachedID)
            let mainCachedParser = mainCachedURL.flatMap { try? InfoPlistParser(plistURL: $0) }
            let initialBundleID = mainCachedParser?.bundleIdentifier ?? context.targetBundleIdentifier

            let targets: [InfoPlistTarget] = {
                guard let targetAppBundle = context.targetAppBundle else {
                    let mainPlist = mainCachedParser?.rawDictionary ?? ["CFBundleIdentifier": context.targetBundleIdentifier]
                    return [InfoPlistTarget(id: initialBundleID, initialPlist: mainPlist)]
                }
                var list: [InfoPlistTarget] = []
                let mainPlist = mainCachedParser?.rawDictionary ?? targetAppBundle.infoPlist
                list.append(InfoPlistTarget(id: initialBundleID, name: targetAppBundle.name, isExtension: false, initialPlist: mainPlist))

                for ext in targetAppBundle.allAppBundles where ext.isExtension {
                    let extCachedID = context.installedApp?.appExtensions.first(where: { $0.bundleIdentifier == ext.bundleIdentifier })?.resignedBundleIdentifier ?? ext.bundleIdentifier
                    let extCachedURL = InstalledApp.customInfoPlistURL(forBundleIdentifier: cacheFolderID, targetID: extCachedID)
                    let extPlist = extCachedURL.flatMap { try? InfoPlistParser(plistURL: $0).rawDictionary } ?? ext.infoPlist
                    list.append(InfoPlistTarget(id: ext.bundleIdentifier, name: ext.name, isExtension: true, initialPlist: extPlist))
                }
                return list
            }()

            self.setProgress(40)

            guard let result = try await handler.resolveInfoPlistCustomization(
                targets: targets,
                initialBundleID: initialBundleID,
                appendTeamID: context.appendTeamID,
                installedAppIdentities: installedAppIdentities,
                teamID: teamID
            ) else {
                throw OperationError.cancelled
            }

            context.appendTeamID = result.appendTeamID

            let mainModifiedPlist = result.modifiedPlists[initialBundleID] ?? [:]
            let customID = InfoPlistParser(dictionary: mainModifiedPlist).bundleIdentifier
            if let customID = customID, !customID.isEmpty, customID != context.bundleIdentifier {
                context.customBundleIdentifier = customID
            } else {
                context.customBundleIdentifier = nil
            }

            for (targetID, plist) in result.modifiedPlists {
                let key = (targetID == initialBundleID) ? context.targetBundleIdentifier : targetID
                context.customInfoPlistByBundleID[key] = plist
            }

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
                try? targetAppBundle.updateInfoPlist(with: mainModifiedPlist)
                for ext in targetAppBundle.allAppBundles where ext.isExtension {
                    if let extPlist = result.modifiedPlists[ext.bundleIdentifier] {
                        try? ext.updateInfoPlist(with: extPlist)
                    }
                }
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
            let cacheFolderID = context.installedApp?.bundleIdentifier ?? context.bundleIdentifier
            let mainTargetID = context.targetBundleIdentifier
            self.setProgress(70)

            let mainCachedID = context.installedApp?.resignedBundleIdentifier ?? mainTargetID
            let targets: [EntitlementsTarget] = {
                guard let targetAppBundle = context.targetAppBundle else {
                    let cachedEntitlements = InstalledApp.customEntitlements(forBundleIdentifier: cacheFolderID, targetID: mainCachedID) ?? [:]
                    return [
                        EntitlementsTarget(
                            id: mainTargetID,
                            name: mainTargetID,
                            isExtension: false,
                            initialEntitlements: cachedEntitlements
                        )
                    ]
                }

                let mainCachedEntitlements = InstalledApp.customEntitlements(forBundleIdentifier: cacheFolderID, targetID: mainCachedID)
                    ?? targetAppBundle.entitlements

                var list: [EntitlementsTarget] = [
                    EntitlementsTarget(
                        id: mainTargetID,
                        name: targetAppBundle.name,
                        isExtension: false,
                        initialEntitlements: mainCachedEntitlements
                    )
                ]

                for ext in targetAppBundle.allAppBundles where ext.isExtension {
                    let extCachedID = context.installedApp?.appExtensions.first(where: { $0.bundleIdentifier == ext.bundleIdentifier })?.resignedBundleIdentifier ?? ext.bundleIdentifier
                    let extCachedEntitlements = InstalledApp.customEntitlements(forBundleIdentifier: cacheFolderID, targetID: extCachedID)
                        ?? ext.entitlements

                    list.append(
                        EntitlementsTarget(
                            id: ext.bundleIdentifier,
                            name: ext.name,
                            isExtension: true,
                            initialEntitlements: extCachedEntitlements
                        )
                    )
                }
                return list
            }()

            guard let result = try await handler.resolveEntitlementsCustomization(
                targets: targets,
                teamType: authTeam.type
            ) else {
                throw OperationError.cancelled
            }

            for (targetID, targetEntitlements) in result {
                context.customEntitlementsByBundleID[targetID] = targetEntitlements
            }

            if let mainEntitlements = result[mainTargetID] {
                for (key, value) in mainEntitlements {
                    context.additionalEntitlements[ALTEntitlement(key)] = value
                }
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
