//
//  ClearAppCacheOperation.swift
//  AltStore
//
//  Created by Riley Testut on 9/27/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation
@preconcurrency import AltStoreCore

import Nuke

struct BatchError: ALTLocalizedError {

    enum Code: Int, ALTErrorCode {
        typealias Error = BatchError
        
        case batchError
    }
    var code: Code = .batchError
    var underlyingErrors: [Error]
    
    var errorTitle: String?
    var errorFailure: String?
    
    init(errors: [Error]) {
        self.underlyingErrors = errors
    }
    
    var errorFailureReason: String {
        guard !self.underlyingErrors.isEmpty else { return NSLocalizedString("An unknown error occured.", comment: "") }
        
        let errorMessages = self.underlyingErrors.map { $0.localizedDescription }
        
        let message = errorMessages.joined(separator: "\n\n")
        return message
    }
}

class ClearAppCacheOperation: BaseOperation<OperationContext, Bool>, @unchecked Sendable {
    private let coordinator = NSFileCoordinator()
    private let coordinatorQueue = OperationQueue()
    
    override init(context: OperationContext = OperationContext()) throws {
        self.coordinatorQueue.name = "AltStore - ClearAppCacheOperation Queue"
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> Bool {
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        self.clearNukeCache()
        
        var allErrors = [Error]()
        
        do { try await self.clearTemporaryDirectory() }
        catch { allErrors.append(error) }
        
        do { try await self.removeUninstalledAppBackupDirectories() }
        catch { allErrors.append(error) }
        
        if !allErrors.isEmpty {
            throw OperationError.cacheClearError(errors: allErrors.map { $0.localizedDescription })
        }
        return true
    }
    
    private func clearNukeCache() {
        guard let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache else { return }
        dataCache.removeAll()
    }
    
    private func clearTemporaryDirectory() async throws {
        let intent = NSFileAccessIntent.writingIntent(with: FileManager.default.temporaryDirectory, options: [.forDeleting])
        try await self.coordinator.coordinate(with: [intent], queue: self.coordinatorQueue)
        try self.clearTempDirItems(at: intent.url, coordinatorError: nil)
    }
    
    private func clearTempDirItems(at url: URL, coordinatorError: Error?) throws {
        if let coordinatorError { throw coordinatorError }
        
        let fileURLs = try FileManager.default.contentsOfDirectory(at: url,
                                                                   includingPropertiesForKeys: [],
                                                                   options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        var errors = [Error]()
        for fileURL in fileURLs {
            do {
                self.verboseLog("[ClearAppCacheOperation] Removing item from temporary directory: \(fileURL.lastPathComponent)")
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                self.debugLog("[ClearAppCacheOperation] Failed to remove \(fileURL.lastPathComponent) from temporary directory. \(error.localizedDescription)")
                errors.append(error)
            }
        }
        
        if !errors.isEmpty {
            throw OperationError.cacheClearError(errors: errors.map { $0.localizedDescription })
        }
    }
    
    private func removeUninstalledAppBackupDirectories() async throws {
        guard let backupsDirectory = FileManager.default.appBackupsDirectory else {
            throw OperationError.missingAppGroup
        }
        
        let installedAppBundleIDs = await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            Set(InstalledApp.all(in: context).map { $0.bundleIdentifier })
        }
        
        let intent = NSFileAccessIntent.writingIntent(with: backupsDirectory, options: [.forDeleting])
        try await self.coordinator.coordinate(with: [intent], queue: self.coordinatorQueue)
        try self.removeBackupDirItems(at: intent.url, installedBundleIDs: installedAppBundleIDs, coordinatorError: nil)
    }
    
    private func removeBackupDirItems(at url: URL, installedBundleIDs: Set<String>, coordinatorError: Error?) throws {
        if let coordinatorError { throw coordinatorError }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }
        
        let fileURLs = try FileManager.default.contentsOfDirectory(at: url,
                                                                   includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                                                                   options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        var errors = [Error]()
        for backupDirectory in fileURLs {
            do {
                let resourceValues = try backupDirectory.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                guard let isDir = resourceValues.isDirectory, let bundleID = resourceValues.name else { continue }
                
                if isDir && !installedBundleIDs.contains(bundleID) && !AppManager.shared.isActivelyManagingApp(withBundleID: bundleID) {
                    self.verboseLog("[ClearAppCacheOperation] Removing backup directory for uninstalled app: \(bundleID)")
                    try FileManager.default.removeItem(at: backupDirectory)
                }
            } catch {
                self.debugLog("[ClearAppCacheOperation] Failed to remove app backup directory. \(error.localizedDescription)")
                errors.append(error)
            }
        }
        
        if !errors.isEmpty {
            throw OperationError.cacheClearError(errors: errors.map { $0.localizedDescription })
        }
    }
}

extension NSFileCoordinator {
    func coordinate(with intents: [NSFileAccessIntent], queue: OperationQueue) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.coordinate(with: intents, queue: queue) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
