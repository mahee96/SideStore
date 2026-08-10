//
//  ALTApplication+AltStoreApp.swift
//  AltStore
//
//  Created by Riley Testut on 11/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
@preconcurrency import AltSign

extension ALTApplication {
    static let altstoreBundleID: String = Bundle.Info.appbundleIdentifier
    static var activeBundleID: String   { Bundle.Info.activeBundleIdentifier }
    
    var isAltStoreApp: Bool {
        if self.fileURL.standardizedFileURL == Bundle.Info.activeBundleURL.standardizedFileURL {
            return true
        }
        let matchesActiveBundle   = !Self.activeBundleID.isEmpty && self.bundleIdentifier.contains(Self.activeBundleID)
        let matchesAltStoreBundle = !Self.altstoreBundleID.isEmpty && self.bundleIdentifier.contains(Self.altstoreBundleID)
        
        return matchesActiveBundle || matchesAltStoreBundle
    }
}