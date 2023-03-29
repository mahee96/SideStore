//
//  ALTApplication+AltStoreApp.swift
//  AltStore
//
//  Created by Riley Testut on 11/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import AltSign

extension ALTApplication
{
    static let altstoreBundleID = Bundle.Info.appbundleIdentifier
    static let altstoreBundleIDOriginal = "AltStore"
    static let storeBundleID = "SideStore"
    static let widgetID = "Widget"    
    
    var isAltStoreApp: Bool {
        let isAltStoreApp = ( self.bundleIdentifier.contains(ALTApplication.altstoreBundleID) || self.bundleIdentifier.contains(ALTApplication.altstoreBundleIDOriginal) || self.bundleIdentifier.contains(ALTApplication.storeBundleID) ) && !self.bundleIdentifier.contains(ALTApplication.widgetID)
        return isAltStoreApp
    }
}
