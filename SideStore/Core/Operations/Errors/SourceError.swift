//
//  SourceError.swift
//  AltStore
//
//  Created by Riley Testut on 5/3/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

extension SourceError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = SourceError
        
        case unsupported
        case duplicateBundleID
        case duplicateVersion
        
        case blocked
        case changedID
        case duplicate
        
        case missingPermissionUsageDescription
        case missingScreenshotSize
        
        case marketplaceNotSupported = 101
        case marketplaceRequired
    }
    
    static func unsupported(_ source: Source) -> SourceError { SourceError(code: .unsupported, source: source) }
    static func duplicateBundleID(_ bundleID: String, source: Source) -> SourceError { SourceError(code: .duplicateBundleID, source: source, bundleID: bundleID) }
    static func duplicateVersion(_ version: String, for app: StoreApp, source: Source) -> SourceError { SourceError(code: .duplicateVersion, source: source, app: app, version: version) }
    
    static func blocked(_ source: Source, bundleIDs: [String]?, existingSource: Source?) -> SourceError { SourceError(code: .blocked, source: source, existingSource: existingSource, bundleIDs: bundleIDs) }
    static func changedID(_ identifier: String, previousID: String, source: Source) -> SourceError { SourceError(code: .changedID, source: source, sourceID: identifier, previousSourceID: previousID) }
    static func duplicate(_ source: Source, existingSource: Source?) -> SourceError { SourceError(code: .duplicate, source: source, existingSource: existingSource) }
    
    static func missingPermissionUsageDescription(for permission: any ALTAppPermission, app: StoreApp, source: Source) -> SourceError {
        SourceError(code: .missingPermissionUsageDescription, source: source, app: app, permission: permission)
    }
    
    static func missingScreenshotSize(for screenshot: AppScreenshot, source: Source) -> SourceError {
        SourceError(code: .missingScreenshotSize, source: source, app: screenshot.app, screenshotURL: screenshot.imageURL)
    }
    
    static func marketplaceNotSupported(source: Source) -> SourceError {
        return SourceError(code: .marketplaceNotSupported, source: source)
    }
    
    static func marketplaceRequired(source: Source) -> SourceError {
        return SourceError(code: .marketplaceRequired, source: source)
    }
}

struct SourceError: ALTLocalizedError
{
    let code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    @Managed var source: Source
    
    @Managed var app: StoreApp?
    @Managed var existingSource: Source?
    var version: String?
    var bundleID: String?
    var bundleIDs: [String]?
        
    // Store in userInfo so they can be viewed from Error Log.
    @UserInfoValue var sourceID: String?
    @UserInfoValue var previousSourceID: String?
    
    @UserInfoValue
    var permission: (any ALTAppPermission)?
    
    @UserInfoValue
    var screenshotURL: URL?
    
    var errorFailureReason: String {
        switch self.code
        {
        case .unsupported: return localized("The source “\(self.$source.name)” is not supported by this version of SideStore.")
        case .duplicateBundleID:
            let bundleIDFragment = self.bundleID.map { localized("the bundle identifier \($0)") } ?? localized("the same bundle identifier")
            let failureReason = localized("The source “\(self.$source.name)” contains multiple apps with \(bundleIDFragment).")
            return failureReason
            
        case .duplicateVersion:
            var versionFragment = localized("duplicate versions")
            if let version
            {
                versionFragment += " (\(version))"
            }
            
            let appFragment: String
            if let name = self.$app.name, let bundleID = self.$app.bundleIdentifier
            {
                appFragment = name + " (\(bundleID))"
            }
            else
            {
                appFragment = localized("one or more apps")
            }
            
            let failureReason = localized("The source “\(self.$source.name)” contains \(versionFragment) for \(appFragment).")
            return failureReason
            
        case .blocked:
            let failureReason = localized("The source “\(self.$source.name)” has been blocked by SideStore for security reasons.")
            return failureReason
            
        case .changedID:
            let failureReason = localized("The identifier of the source “\(self.$source.name)” has changed.")
            return failureReason
            
        case .duplicate:
            let baseMessage = localized("A source with the identifier '\(self.$source.identifier)' already exists")
            guard let existingSourceName = self.$existingSource.name else { return baseMessage + "." }
            
            let failureReason = baseMessage + " (“\(existingSourceName)”)."
            return failureReason
            
        case .missingPermissionUsageDescription:
            let appName = self.$app.name ?? localized("an app in source “\(self.$source.name)”")
            guard let permission else {
                return localized("A permission for \(appName) is missing a usage description.")
            }
            
            let permissionType = permission.type.localizedName ?? localized("Permission")
            let failureReason = localized("The \(permissionType) '\(permission.rawValue)' for \(appName) is missing a usage description.")
            return failureReason
            
        case .missingScreenshotSize:
            let appName = self.$app.name ?? localized("an app in source “\(self.$source.name)”")
            let baseMessage = localized("An iPad screenshot for \(appName) does not specify its size")
            guard let screenshotURL else { return baseMessage + "." }
            
            let failureReason = baseMessage + ": \(screenshotURL.absoluteString)"
            return failureReason
            
        case .marketplaceNotSupported:
            let failureReason = localized("The source “\(self.$source.name)” contains notarized apps, which are not supported by this version of SideStore.")
            return failureReason
            
        case .marketplaceRequired:
            let failureReason = localized("One or more apps in source “\(self.$source.name)” are missing a marketplaceID. This most likely means they are not notarized, which is not supported by this version of SideStore.")
            return failureReason
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .blocked:
            if self.existingSource != nil
            {
                // Source already added, so tell them to remove it + any installed apps.
                if let blockedAppNames = self.blockedAppNames
                {
                    let recoverySuggestion = localized("For your protection, please remove the source and uninstall the following apps:") + "\n\n" + blockedAppNames.joined(separator: "\n")
                    return recoverySuggestion
                }
                else
                {
                    let recoverySuggestion = localized("For your protection, please remove the source and uninstall all apps downloaded from it.")
                    return recoverySuggestion
                }
            }
            else
            {
                // Source is not already added, so no need to tell users to remove it.
                // Instead, we just list all affected apps (if provided).
                guard let blockedAppNames else { return nil }
                
                let recoverySuggestion = localized("The following apps have been flagged:") + "\n\n" + blockedAppNames.joined(separator: "\n")
                return recoverySuggestion
            }
            
        case .changedID: return localized("A source cannot change its identifier once added. This source can no longer be updated.")
        case .duplicate:
            let recoverySuggestion = localized("Please remove the existing source in order to add this one.")
            return recoverySuggestion
            
        case .marketplaceRequired:
            let failureReason = localized("SideStore can only install marketplace apps that have been notarized by Apple.")
            return failureReason
            
        default: return nil
        }
    }
}

private extension SourceError
{
    var blockedAppNames: [String]? {
        let blockedAppNames: [String]?
        
        if let existingSource
        {
            // Blocked apps = all installed apps from this source.
            blockedAppNames = self.$existingSource.perform { _ in
                let storeApps = existingSource.apps.lazy.filter { $0.installedApp != nil }
                guard !storeApps.isEmpty else { return nil }
                
                let appNames = storeApps.map { "\($0.name) (\($0.bundleIdentifier))" }
                return Array(appNames)
            }
        }
        else if let bundleIDs
        {
            // Blocked apps = explicitly listed bundleIDs in blocked source JSON entry.
            blockedAppNames = self.$source.perform { source in
                bundleIDs.compactMap { (bundleID) in
                    guard let storeApp = source._apps.lazy.compactMap({ $0 as? StoreApp }).first(where: { $0.bundleIdentifier == bundleID }) else { return nil }
                    return "\(storeApp.name) (\(storeApp.bundleIdentifier))"
                }
            }
        }
        else
        {
            blockedAppNames = nil
        }

        let sortedNames = blockedAppNames?.sorted { $0.localizedCompare($1) == .orderedAscending }
        return sortedNames
    }
}
