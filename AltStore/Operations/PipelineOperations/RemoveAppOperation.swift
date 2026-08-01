//
//  RemoveAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
@preconcurrency import AltStoreCore

final class RemoveAppOperation: BasePipelineOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        debugLog("[RemoveAppOperation] execute() started")
        defer { debugLog("[RemoveAppOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        guard let installedApp = self.context.installedApp else {
            throw OperationError.invalidParameters("RemoveAppOperation.main: self.context.installedApp is nil")
        }
        
        let bundleID = await installedApp.managedObjectContext?.perform { installedApp.bundleIdentifier }
        if bundleID == Bundle.main.bundleIdentifier || bundleID == StoreApp.altstoreAppID {
            throw OperationError.invalidParameters("SideStore cannot delete itself.")
        }
        
        let resignedBundleIdentifier = await installedApp.managedObjectContext?.perform {
            self.resignedBundleIdentifier(for: installedApp)
        }
        guard let resignedBundleIdentifier else {
            throw OperationError.invalidParameters("RemoveAppOperation: installedApp.managedObjectContext is nil")
        }
        
        try await removeApp(resignedBundleIdentifier)
        
        guard let backgroundContext = self.context.dbBackgroundContext else {
            throw OperationError.invalidParameters("RemoveAppOperation: context.dbBackgroundContext is nil")
        }
        try await backgroundContext.perform {
            _ = self.markInactive(installedApp, in: backgroundContext)
        }
        
        let result = try await backgroundContext.perform {
            return backgroundContext.object(with: installedApp.objectID) as! InstalledApp
        }
        self.setProgress(100)
        return result
    }
    
    private func resignedBundleIdentifier(for installedApp: InstalledApp) -> String {
        installedApp.resignedBundleIdentifier
    }
    
    private func markInactive(_ installedApp: InstalledApp, in backgroundContext: NSManagedObjectContext) -> InstalledApp {
        self.setProgress(self.progress.completedUnitCount + 1)
        let installedApp = backgroundContext.object(with: installedApp.objectID) as! InstalledApp
        installedApp.isActive = false
        return installedApp
    }
}

