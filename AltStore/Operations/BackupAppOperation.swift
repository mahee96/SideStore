//
//  BackupAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

extension BackupAppOperation {
    enum Action: String {
        case backup
        case restore
    }
}

final class BackupAppOperation: BaseOperation<InstallAppOperationContext, URL>, @unchecked Sendable {
    let action: Action
    
    private var appName: String?
    
    init(action: Action, context: InstallAppOperationContext) throws {
        self.action = action
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> URL {
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        guard let installedApp = context.installedApp else {
            throw OperationError.invalidParameters("BackupAppOperation.execute: context.installedApp is nil")
        }
        
        try await self.openAppAndObserve(installedApp: installedApp)
        return installedApp.fileURL
    }
    
    private func constructBackupURLs(for installedApp: InstalledApp) throws -> (openURL: URL, returnURL: URL) {
        let appName = installedApp.name
        self.appName = appName
        
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let altstoreOpenURL = URL(string: "sidestore-\(bundleIdentifier)://")
        else {
            throw OperationError.openAppFailed(name: appName)
        }

        var returnURLComponents = URLComponents(url: altstoreOpenURL, resolvingAgainstBaseURL: false)
        returnURLComponents?.host = "appBackupResponse"
        guard let returnURL = returnURLComponents?.url else { throw OperationError.openAppFailed(name: appName) }

        var openURLComponents = URLComponents()
        openURLComponents.scheme = installedApp.openAppURL.scheme
        openURLComponents.host = self.action.rawValue
        openURLComponents.queryItems = [URLQueryItem(name: "returnURL", value: returnURL.absoluteString)]
        
        guard let openURL = openURLComponents.url else { throw OperationError.openAppFailed(name: appName) }
        return (openURL, returnURL)
    }

    private func mapBackupError(_ error: Error) -> Error {
        let appName = self.appName ?? self.context.bundleIdentifier
        
        switch (error, self.action) {
        case (let error as NSError, _) where (self.context.error as NSError?) == error: fallthrough
        case (is CancellationError, _):
            return error
            
        case (let error as NSError, .backup):
            let localizedFailure = String(format: NSLocalizedString("Could not back up “%@”.", comment: ""), appName)
            return error.withLocalizedFailure(localizedFailure)
            
        case (let error as NSError, .restore):
            let localizedFailure = String(format: NSLocalizedString("Could not restore “%@”.", comment: ""), appName)
            return error.withLocalizedFailure(localizedFailure)
        }
    }

    @MainActor
    private func openApp(url: URL) async -> Bool {
        let currentTime = CFAbsoluteTimeGetCurrent()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            UIApplication.shared.open(url, options: [:]) { success in
                let elapsedTime = CFAbsoluteTimeGetCurrent() - currentTime
                if success {
                    continuation.resume(returning: true)
                } else if elapsedTime < 0.5 {
                    self.debugLog("Failed to open app too quickly, retrying after a few seconds...")
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        UIApplication.shared.open(url, options: [:]) { retrySuccess in
                            continuation.resume(returning: retrySuccess)
                        }
                    }
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func openAppAndObserve(installedApp: InstalledApp) async throws {
        let (openURL, _) = try self.constructBackupURLs(for: installedApp)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var timeoutTimer: Timer?
            var applicationWillReturnObserver: NSObjectProtocol?
            var backupResponseObserver: NSObjectProtocol?
            var hasResumed = false

            let removeObservers = {
                timeoutTimer?.invalidate()
                if let observer = applicationWillReturnObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                if let observer = backupResponseObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
            }

            applicationWillReturnObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { _ in
                timeoutTimer?.invalidate()
                if let observer = applicationWillReturnObserver { NotificationCenter.default.removeObserver(observer) }
                if let observer = backupResponseObserver { NotificationCenter.default.removeObserver(observer) }
                
                timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !hasResumed else { return }
                        hasResumed = true
                        removeObservers()
                        AppDelegate.dumpSideBackupLogsIfNeeded()
                        continuation.resume(throwing: OperationError.timedOut)
                    }
                }
            }
            
            backupResponseObserver = NotificationCenter.default.addObserver(
                forName: AppDelegate.appBackupDidFinish,
                object: nil,
                queue: nil
            ) { notification in
                guard !hasResumed else { return }
                hasResumed = true
                removeObservers()
                AppDelegate.dumpSideBackupLogsIfNeeded()
                
                let result = notification.userInfo?[AppDelegate.appBackupResultKey] as? Result<Void, Error> ?? .failure(OperationError.unknownResult)
                let mappedResult = result.mapError { self.mapBackupError($0) }
                if case .success = mappedResult {
                    self.progress.completedUnitCount += 1
                }
                continuation.resume(with: mappedResult)
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                let openedSuccessfully = await self.openApp(url: openURL)
                if !openedSuccessfully {
                    guard !hasResumed else { return }
                    hasResumed = true
                    removeObservers()
                    continuation.resume(throwing: OperationError.openAppFailed(name: installedApp.name))
                }
            }
        }
    }
}
