//
//  PatchAppIconOperation.swift
//  AltStore
//
//  Created by Magesh K on 23/7/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

@preconcurrency import UIKit
@preconcurrency import AltStoreCore

final class PatchAppIconOperation: BaseOperation<InstallAppOperationContext, URL>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> URL {
        debugLog("[PatchAppIconOperation] execute() started")
        defer { debugLog("[PatchAppIconOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        
        guard let app = self.context.app else {
            throw OperationError.invalidParameters("PatchAppIconOperation.execute: self.context.app is nil")
        }
        
        guard let alternateIconURL = self.context.alternateIconURL,
              FileManager.default.fileExists(atPath: alternateIconURL.path) else {
            if case .remove = self.context.alternateIconMode {
                let appBundleURL = app.fileURL
                let plistURL = appBundleURL.appendingPathComponent("Info.plist")
                
                // Remove AltIcon files from the bundle directory
                let fm = FileManager.default
                let iconPattern = "AltIcon"
                if let contents = try? fm.contentsOfDirectory(at: appBundleURL, includingPropertiesForKeys: nil) {
                    for fileURL in contents {
                        if fileURL.lastPathComponent.hasPrefix(iconPattern) {
                            try? fm.removeItem(at: fileURL)
                        }
                    }
                }
                
                // Revert Info.plist CFBundleIcons
                if var infoPlist = NSMutableDictionary(contentsOf: plistURL) as? [String: Any] {
                    if let originalIcons = infoPlist["CFBundleIcons~original"] {
                        infoPlist["CFBundleIcons"] = originalIcons
                    } else {
                        infoPlist.removeValue(forKey: "CFBundleIcons")
                    }
                    
                    if let originalIpadIcons = infoPlist["CFBundleIcons~ipad~original"] {
                        infoPlist["CFBundleIcons~ipad"] = originalIpadIcons
                    } else {
                        infoPlist.removeValue(forKey: "CFBundleIcons~ipad")
                    }
                    
                    infoPlist.removeValue(forKey: "CFBundleIcons~original")
                    infoPlist.removeValue(forKey: "CFBundleIcons~ipad~original")
                    
                    if let plistData = try? PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0) {
                        try? plistData.write(to: plistURL, options: .atomic)
                    }
                }
            }
            return app.fileURL
        }
        
        let appBundleURL = app.fileURL
        
        let data = try Data(contentsOf: alternateIconURL)
        guard let image = UIImage(data: data) else {
            throw OperationError.invalidParameters("Invalid icon image data")
        }
        
        let iconScale = await MainActor.run { Int(UIScreen.main.scale) }
        guard let icon = image.resizing(toFill: CGSize(width: 60 * iconScale, height: 60 * iconScale)),
              let iconData = icon.pngData()
        else {
            throw OperationError.invalidParameters("Failed to resize icon image")
        }
        
        let iconName = "AltIcon"
        let iconURL = appBundleURL.appendingPathComponent(iconName + "@\(iconScale)x.png")
        try iconData.write(to: iconURL, options: .atomic)
        
        let plistURL = appBundleURL.appendingPathComponent("Info.plist")
        guard var infoPlist = NSMutableDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw OperationError.invalidParameters("Failed to load Info.plist from app bundle")
        }
        
        // Backup original CFBundleIcons if not already backed up
        if infoPlist["CFBundleIcons~original"] == nil {
            infoPlist["CFBundleIcons~original"] = infoPlist["CFBundleIcons"]
        }
        if infoPlist["CFBundleIcons~ipad~original"] == nil {
            infoPlist["CFBundleIcons~ipad~original"] = infoPlist["CFBundleIcons~ipad"]
        }
        
        let iconDictionary = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": [iconName]]]
        infoPlist["CFBundleIcons"] = iconDictionary
        
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: plistURL, options: .atomic)
        return app.fileURL
    }
}
