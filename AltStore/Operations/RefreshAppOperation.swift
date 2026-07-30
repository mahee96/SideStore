//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class RefreshAppOperation: AsyncOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> InstalledApp {
        try await super.execute(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        
        guard let profiles = self.context.provisioningProfiles else {
            throw OperationError.invalidParameters("RefreshAppOperation.execute: self.context.provisioningProfiles is nil")
        }
        
        guard let app = self.context.app else { throw OperationError(.appNotFound(name: nil)) }
        for p in profiles {
            do {
                try await installProvisioningProfiles(p.value.data)
            } catch {
                throw MinimuxerWrapperError.profileInstall
            }
        }
        
        guard let dbContext = self.context.dbBackgroundContext else {
            throw OperationError.invalidParameters("RefreshAppOperation: context.dbBackgroundContext is nil")
        }
        
        let installedApp = try await dbContext.perform {
            try self.updateInstalledApp(for: app, profiles: profiles, in: dbContext)
        }
        
        try await dbContext.perform {
            try dbContext.save()
        }
        
        return installedApp
    }
    
    private func updateInstalledApp(for app: ALTApplication, profiles: [String: ALTProvisioningProfile], in dbContext: NSManagedObjectContext) throws -> InstalledApp {
        self.progress.completedUnitCount += 1
        
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), self.context.bundleIdentifier)
        guard let installedApp = InstalledApp.first(satisfying: predicate, in: dbContext) else {
            throw OperationError(.appNotFound(name: app.name))
        }
        installedApp.update(provisioningProfile: profiles.values.first!)
        for installedExtension in installedApp.appExtensions {
            guard let provisioningProfile = profiles[installedExtension.bundleIdentifier] else { continue }
            installedExtension.update(provisioningProfile: provisioningProfile)
        }
        return installedApp
    }
}
