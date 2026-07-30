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

final class InstallBackupAppOperation: BaseOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    let app: InstalledApp

    init(app: InstalledApp, context: InstallAppOperationContext) throws {
        self.app = app
        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> InstalledApp {
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)

        guard ALTApplication(fileURL: app.fileURL) != nil else {
            throw OperationError.appNotFound(name: app.name)
        }

        let temporaryDirectoryURL = context.temporaryDirectory.appendingPathComponent("SideBackup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        guard let sidebackupFileURL = Bundle.main.url(forResource: "SideBackup", withExtension: "ipa") else {
            throw OperationError.appNotFound(name: "SideBackup")
        }

        let unzippedAppBundleURL = try FileManager.default.unzipAppBundle(at: sidebackupFileURL, toDirectory: temporaryDirectoryURL)
        guard let unzippedAppBundle = Bundle(url: unzippedAppBundleURL) else {
            throw OperationError.invalidApp
        }

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

        guard let backupApp = ALTApplication(fileURL: unzippedAppBundleURL) else {
            throw OperationError.invalidApp
        }
        context.app = backupApp
        return app
    }
}
