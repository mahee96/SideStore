//
//  DeactivateAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 3/4/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign
import CoreData

final class DeactivateAppOperation: BaseOperation<OperationContext, InstalledApp>, @unchecked Sendable
{
    let app: InstalledApp
    
    init(app: InstalledApp, context: OperationContext) throws {
        self.app = app
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> InstalledApp {
        debugLog("[DeactivateAppOperation] execute() started")
        defer { debugLog("[DeactivateAppOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        guard let backgroundContext = self.context.dbBackgroundContext else {
            throw OperationError.invalidParameters("DeactivateAppOperation: context.dbBackgroundContext is nil")
        }
        let installedApp = await backgroundContext.perform {
            backgroundContext.object(with: self.app.objectID) as! InstalledApp
        }

        try await self.performDeactivate(for: installedApp)
        return await backgroundContext.perform {
            backgroundContext.object(with: self.app.objectID) as! InstalledApp
        }
    }
    
    @discardableResult
    private func performDeactivate(for installedApp: InstalledApp) async throws -> InstalledApp {
        let appExIdentifiers = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
        let allIdentifiers = [installedApp.resignedBundleIdentifier] + appExIdentifiers

        var removedAny = false
        for identifier in allIdentifiers {
            try await removeProvisioningProfile(identifier)
            self.progress.completedUnitCount += 1
            removedAny = true
        }
        guard removedAny else {
            throw OperationError.invalidParameters("DeactivateAppOperation: no profiles found to remove")
        }
        installedApp.isActive = false
        return installedApp
    }
}

