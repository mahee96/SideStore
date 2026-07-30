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
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        
        guard let app = self.context.app else {
            throw OperationError.invalidParameters("PatchAppIconOperation.execute: self.context.app is nil")
        }
        
        guard let alternateIconURL = self.context.alternateIconURL,
              FileManager.default.fileExists(atPath: alternateIconURL.path) else {
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
        
        let iconDictionary = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": [iconName]]]
        infoPlist["CFBundleIcons"] = iconDictionary
        
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: plistURL, options: .atomic)
        return app.fileURL
    }
}
