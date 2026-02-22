//
//  AnalyticsManager.swift
//  AltStore
//
//  Created by Riley Testut on 3/31/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

#if DEBUG
private let appCenterAppSecret = "73532d3e-e573-4693-99a4-9f85840bbb44"
#elseif RELEASE
private let appCenterAppSecret = "73532d3e-e573-4693-99a4-9f85840bbb44"
#else
private let appCenterAppSecret = "73532d3e-e573-4693-99a4-9f85840bbb44"
#endif

extension AnalyticsManager
{
    enum EventProperty: String
    {
        case name
        case bundleIdentifier
        case developerName
        case version
        case buildVersion
        case size
        case tintColor
        case sourceIdentifier
        case sourceURL
        case patreonURL
        case pledgeAmount
        case pledgeCurrency
    }
    
    enum Event
    {
        case installedApp(InstalledApp)
        case updatedApp(InstalledApp)
        case refreshedApp(InstalledApp)
        
        var name: String {
            switch self
            {
            case .installedApp: return "installed_app"
            case .updatedApp: return "updated_app"
            case .refreshedApp: return "refreshed_app"
            }
        }
        
        var properties: [EventProperty: String] {
            let properties: [EventProperty: String?]
            
            switch self
            {
            case .installedApp(let app), .updatedApp(let app), .refreshedApp(let app):
                let appBundleURL = InstalledApp.fileURL(for: app)
                let appBundleSize = FileManager.default.directorySize(at: appBundleURL)
                
                properties = [
                    .name: app.name,
                    .bundleIdentifier: app.bundleIdentifier,
                    .developerName: app.storeApp?.developerName,
                    .version: app.version,
                    .buildVersion: app.buildVersion,
                    .size: appBundleSize?.description,
                    .tintColor: app.storeApp?.tintColor?.hexString,
                    .sourceIdentifier: app.storeApp?.sourceIdentifier,
                    .sourceURL: app.storeApp?.source?.sourceURL.absoluteString,
                    .patreonURL: app.storeApp?.source?.patreonURL?.absoluteString,
                    .pledgeAmount: app.storeApp?.pledgeAmount?.description,
                    .pledgeCurrency: app.storeApp?.pledgeCurrency
                ]
            }
            
            return properties.compactMapValues { $0 }
        }
    }
}
