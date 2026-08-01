//
//  InstallBackupAppOperation.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class InstallBackupAppOperation: BasePipelineOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    let app: InstalledApp?

    init(app: InstalledApp?, context: InstallAppOperationContext) throws {
        self.app = app
        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        debugLog("[InstallBackupAppOperation] execute() started")
        defer { debugLog("[InstallBackupAppOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        guard let app = self.app else {
            throw OperationError.invalidParameters("InstallBackupAppOperation: target app is nil")
        }
        
        guard ALTApplication(fileURL: app.fileURL) != nil else {
            throw OperationError.appNotFound(name: app.name)
        }

        self.setProgress(20)
        let temporaryDirectoryURL = context.temporaryDirectory.appendingPathComponent("SideBackup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        guard let sidebackupFileURL = Bundle.main.url(forResource: "SideBackup", withExtension: "ipa") else {
            throw OperationError.appNotFound(name: "SideBackup")
        }

        self.setProgress(40)
        let unzippedAppBundleURL = try FileManager.default.unzipAppBundle(at: sidebackupFileURL, toDirectory: temporaryDirectoryURL)
        guard let unzippedAppBundle = Bundle(url: unzippedAppBundleURL) else {
            throw OperationError.invalidApp
        }

        self.setProgress(70)
        if var infoDictionary = unzippedAppBundle.infoDictionary {
            infoDictionary["CFBundleDisplayName"] = app.name
            infoDictionary[kCFBundleIdentifierKey as String] = context.targetBundleIdentifier

            let installedAppUTI = [
                "UTTypeConformsTo": [],
                "UTTypeDescription": "SideStore Backup App",
                "UTTypeIconFiles": [],
                "UTTypeIdentifier": app.installedBackupAppUTI,
                "UTTypeTagSpecification": [:]
            ] as [String: Any]

            var exportedUTIs = infoDictionary[Bundle.Info.exportedUTIs] as? [[String: Any]] ?? []
            exportedUTIs.append(installedAppUTI)
            infoDictionary[Bundle.Info.exportedUTIs] = exportedUTIs

            if let cachedApp = ALTApplication(fileURL: app.fileURL), let icon = cachedApp.icon?.resizing(to: CGSize(width: 180, height: 180)) {
                let iconFileURL = unzippedAppBundleURL.appendingPathComponent("AppIcon.png")
                if let iconData = icon.pngData() {
                    try? iconData.write(to: iconFileURL, options: .atomic)
                    let bundleIcons = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": [iconFileURL.lastPathComponent]]]
                    infoDictionary["CFBundleIcons"] = bundleIcons
                }
            }

            try (infoDictionary as NSDictionary).write(to: unzippedAppBundle.infoPlistURL)
        }

        self.setProgress(90)
        guard let backupApp = ALTApplication(fileURL: unzippedAppBundleURL) else {
            throw OperationError.invalidApp
        }
        context.app = backupApp
        self.setProgress(100)
        return app
    }
}
