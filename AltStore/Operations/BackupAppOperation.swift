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
    
    override func execute(parentProgress: Progress?) async throws -> URL {
        self.debugLog("[BackupAppOperation] execute() started. Action: \(action.rawValue)")
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        guard let installedApp = context.installedApp else {
            self.debugLog("[BackupAppOperation] Error: context.installedApp is nil")
            throw OperationError.invalidParameters("BackupAppOperation.execute: context.installedApp is nil")
        }
        
        guard let context = installedApp.managedObjectContext else {
            throw OperationError.invalidParameters("BackupAppOperation: installedApp.managedObjectContext is nil")
        }
        let (bundleID, fileURL, name, openAppURL) = context.performAndWait {
            (installedApp.bundleIdentifier, installedApp.fileURL, installedApp.name, installedApp.openAppURL)
        }
        
        self.debugLog("[BackupAppOperation] Ready to open app and observe backup. InstalledApp: \(bundleID)")
        try await self.openAppAndObserve(installedApp: installedApp, bundleIdentifier: bundleID, name: name, openAppURL: openAppURL)
        self.debugLog("[BackupAppOperation] execute() completed successfully.")
        return fileURL
    }
    
    private func constructBackupURLs(bundleIdentifier: String, name: String, openAppURL: URL) throws -> (openURL: URL, returnURL: URL) {
        self.appName = name
        
        guard let appGroupBundleID = Bundle.main.bundleIdentifier,
              let altstoreOpenURL = URL(string: "sidestore-\(appGroupBundleID)://")
        else {
            throw OperationError.openAppFailed(name: name)
        }

        var returnURLComponents = URLComponents(url: altstoreOpenURL, resolvingAgainstBaseURL: false)
        returnURLComponents?.host = "appBackupResponse"
        guard let returnURL = returnURLComponents?.url else { throw OperationError.openAppFailed(name: name) }

        var openURLComponents = URLComponents()
        openURLComponents.scheme = openAppURL.scheme
        openURLComponents.host = self.action.rawValue
        openURLComponents.queryItems = [URLQueryItem(name: "returnURL", value: returnURL.absoluteString)]
        
        guard let openURL = openURLComponents.url else { throw OperationError.openAppFailed(name: name) }
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
        self.debugLog("[BackupAppOperation] openApp() called with URL: \(url.absoluteString)")
        let currentTime = CFAbsoluteTimeGetCurrent()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            UIApplication.shared.open(url, options: [:]) { success in
                let elapsedTime = CFAbsoluteTimeGetCurrent() - currentTime
                self.debugLog("[BackupAppOperation] openApp() completion handler success: \(success), elapsedTime: \(elapsedTime)s")
                if success {
                    continuation.resume(returning: true)
                } else if elapsedTime < 0.5 {
                    self.debugLog("[BackupAppOperation] Failed to open app too quickly, retrying after a few seconds...")
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        UIApplication.shared.open(url, options: [:]) { retrySuccess in
                            self.debugLog("[BackupAppOperation] openApp() retry completion handler success: \(retrySuccess)")
                            continuation.resume(returning: retrySuccess)
                        }
                    }
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func openAppAndObserve(installedApp: InstalledApp, bundleIdentifier: String, name: String, openAppURL: URL) async throws {
        let (openURL, returnURL) = try self.constructBackupURLs(bundleIdentifier: bundleIdentifier, name: name, openAppURL: openAppURL)
        self.debugLog("[BackupAppOperation] openAppAndObserve() constructed URLs. openURL: \(openURL.absoluteString), returnURL: \(returnURL.absoluteString)")
        
        self.debugLog("[BackupAppOperation] Starting observation...")
        
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
                self.debugLog("[BackupAppOperation] willEnterForegroundNotification received. Starting 5-second grace period timer...")
                timeoutTimer?.invalidate()
                if let observer = applicationWillReturnObserver { NotificationCenter.default.removeObserver(observer) }
                
                timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !hasResumed else { return }
                        self.debugLog("[BackupAppOperation] 5-second timer expired without receiving backup completion response. Timing out.")
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
                self.debugLog("[BackupAppOperation] appBackupDidFinish notification received. UserInfo: \(String(describing: notification.userInfo))")
                guard !hasResumed else {
                    self.debugLog("[BackupAppOperation] Warning: already resumed. Ignoring notification.")
                    return
                }
                hasResumed = true
                removeObservers()
                AppDelegate.dumpSideBackupLogsIfNeeded()
                
                let result = notification.userInfo?[AppDelegate.appBackupResultKey] as? Result<Void, Error> ?? .failure(OperationError.unknownResult)
                let mappedResult = result.mapError { self.mapBackupError($0) }
                self.debugLog("[BackupAppOperation] Resuming continuation with mapped result: \(mappedResult)")
                if case .success = mappedResult {
                    self.setProgress(self.progress.completedUnitCount + 1)
                }
                continuation.resume(with: mappedResult)
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                let openedSuccessfully = await self.openApp(url: openURL)
                if !openedSuccessfully {
                    guard !hasResumed else { return }
                    self.debugLog("[BackupAppOperation] Failed to open target application. Resuming with error.")
                    hasResumed = true
                    removeObservers()
                    continuation.resume(throwing: OperationError.openAppFailed(name: installedApp.name))
                }
            }
        }
    }
}
