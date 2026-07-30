//
//  ExportResignedAppOperation.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class ExportResignedAppOperation: BaseOperation<InstallAppOperationContext, URL>, @unchecked Sendable {

    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> URL {
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)

        guard UserDefaults.standard.isExportResignedAppEnabled, let resignedApp = self.context.resignedApp else {
            throw OperationError.invalidParameters("ExportResignedAppOperation: context.resignedApp is nil")
        }

        let sourceURL = resignedApp.fileURL
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let resignedAppsURL = documentsURL.appendingPathComponent("ResignedApps")
        do {
            if !FileManager.default.fileExists(atPath: resignedAppsURL.path) {
                try FileManager.default.createDirectory(at: resignedAppsURL, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            debugLog("Failed to create ResignedApps folder: \(error)")
            throw error
        }

        let utis = Bundle(url: resignedApp.fileURL)?.infoDictionary?[Bundle.Info.exportedUTIs] as? [[String: Any]]
        let isSideBackup = utis?.first?["UTTypeDescription"] as? String == "SideStore Backup App"
        let destPath = isSideBackup ? resignedApp.name + "-sidebackup" : resignedApp.name
        let destinationURL = resignedAppsURL.appendingPathComponent(destPath + ".app")
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
        } catch {
            debugLog("Failed to delete existing file at destination: \(error)")
            throw error
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            debugLog("File copied to: \(destinationURL.path)")
        } catch {
            debugLog("Failed to copy file to destination: \(error)")
            throw error
        }
        return destinationURL
    }
}
