//
//  FetchAppIDsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class FetchAppIDsOperation: AsyncOperation<AuthenticatedOperationContext, ([AppID], NSManagedObjectContext)>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> ([AppID], NSManagedObjectContext) {
        try await super.execute(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        guard
            let team = self.context.team,
            let session = self.context.session
        else {
            throw OperationError.invalidParameters("FetchAppIDsOperation.main: self.context.team or self.context.session is nil")
        }
        
        guard let dbContext = self.context.dbBackgroundContext else {
            throw OperationError.invalidParameters("FetchAppIDsOperation: context.dbBackgroundContext is nil")
        }
        
        let fetchedAppIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
        
        return try await dbContext.perform {
            try self.syncAppIDs(fetchedAppIDs, team: team, in: dbContext)
        }
    }
    
    private func syncAppIDs(_ fetchedAppIDs: [ALTAppID], team: ALTTeam, in dbContext: NSManagedObjectContext) throws -> ([AppID], NSManagedObjectContext) {
        guard let team = Team.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Team.identifier), team.identifier), in: dbContext) else {
            throw OperationError.notAuthenticated
        }
        
        let fetchedIdentifiers = fetchedAppIDs.map { $0.identifier }
        
        let deletedAppIDsRequest = AppID.fetchRequest() as NSFetchRequest<AppID>
        deletedAppIDsRequest.predicate = NSPredicate(format: "%K == %@ AND NOT (%K IN %@)",
                                                     #keyPath(AppID.team), team,
                                                     #keyPath(AppID.identifier), fetchedIdentifiers)
        
        let deletedAppIDs = try dbContext.fetch(deletedAppIDsRequest)
        deletedAppIDs.forEach { dbContext.delete($0) }
        
        let appIDs = fetchedAppIDs.map { AppID($0, team: team, context: dbContext) }
        return (appIDs, dbContext)
    }
}

extension ALTAppleAPI {
    func fetchAppIDs(for team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTAppID] {
        try await withCheckedThrowingContinuation { continuation in
            self.fetchAppIDs(for: team, session: session) { appIDs, error in
                if let appIDs = appIDs {
                    continuation.resume(returning: appIDs)
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
        }
    }
}
