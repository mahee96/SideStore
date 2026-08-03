//
//  RemoveAppExtensionsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class RemoveAppExtensionsOperation: BasePipelineOperation<InstallAppOperationContext, ALTApplication>, @unchecked Sendable {
    let localAppExtensions: Set<ALTApplication>?
    
    init(context: InstallAppOperationContext, localAppExtensions: Set<ALTApplication>?) throws {
        self.localAppExtensions = localAppExtensions
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?) async throws -> ALTApplication {
        debugLog("[RemoveAppExtensionsOperation] execute() started")
        defer { debugLog("[RemoveAppExtensionsOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        guard let targetAppBundle = context.targetAppBundle else {
            throw OperationError.invalidParameters("RemoveAppExtensionsOperation: context.appBundle is nil")
        }
        
        // target App Bundle doesn't contain extensions so don't bother
        guard !targetAppBundle.appExtensions.isEmpty else {
            self.setProgress(100)
            return targetAppBundle
        }
        
        self.setProgress(30)
        let excessExtensions = processExtensionsInfo(from: targetAppBundle, localAppExtensions: localAppExtensions)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                guard UserDefaults.standard.customizeAppExtensions,
                      let presentingViewController = context.authenticatedContext.presentingViewController,
                      presentingViewController.viewIfLoaded?.window != nil else {
                    // perform silent extensions cleanup for those that aren't already present in existing app
                    // background mode: remove only the excess extensions automatically for re-installs
                    //                  keep all extensions for fresh install (localAppBundle = nil)
                    do {
                        try self.removeExtensions(from: excessExtensions, endPercent: 100)
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                self.setProgress(50)
                /// Foreground prompt:
                let firstSentence: String
                if UserDefaults.standard.activeAppLimitIncludesExtensions {
                    firstSentence = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions.", comment: "")
                } else {
                    firstSentence = NSLocalizedString("Non-developer Apple IDs are limited to creating 10 App IDs per week.", comment: "")
                }
                
                let message = firstSentence + " " + NSLocalizedString("Would you like to remove this app's extensions so they don't count towards your limit? There are \(targetAppBundle.appExtensions.count) Extensions", comment: "")
                
                let alertController = UIAlertController(title: NSLocalizedString("App Contains Extensions", comment: ""), message: message, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style, handler: { _ in
                    continuation.resume(throwing: OperationError.cancelled)
                }))
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Keep App Extensions (Use Main Profile)", comment: ""), style: .default) { _ in
                    self.context.useMainProfile = true
                    self.setProgress(100)
                    continuation.resume(returning: ())
                })
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Keep App Extensions (Register App ID for Each Extension)", comment: ""), style: .default) { _ in
                    self.setProgress(100)
                    continuation.resume(returning: ())
                })
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Remove App Extensions", comment: ""), style: .destructive) { _ in
                    do {
                        try self.removeExtensions(from: targetAppBundle.appExtensions, endPercent: 85)
                        try self.updateManifest()
                        self.setProgress(100)
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                })
                
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Choose App Extensions", comment: ""), style: .default) { _ in
                    let popoverContentController = AppExtensionViewHostingController(extensions: targetAppBundle.appExtensions) { selection in
                        do {
                            try self.removeExtensions(from: Set(selection), endPercent: 100)
                            continuation.resume(returning: ())
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                    
                    let suiview = popoverContentController.view!
                    suiview.translatesAutoresizingMaskIntoConstraints = false
                    
                    popoverContentController.modalPresentationStyle = .popover
                    
                    if let popoverPresentationController = popoverContentController.popoverPresentationController {
                        popoverPresentationController.sourceView = presentingViewController.view
                        popoverPresentationController.sourceRect = CGRect(x: 50, y: 50, width: 4, height: 4)
                        popoverPresentationController.delegate = popoverContentController
                        
                        presentingViewController.present(popoverContentController, animated: true)
                    } else {
                        continuation.resume(throwing: OperationError.invalidParameters("RemoveAppExtensionsOperation: popoverContentController.popoverPresentationController is nil"))
                    }
                })
                
                presentingViewController.present(alertController, animated: true) {
                    if presentingViewController.presentedViewController == nil && !alertController.isViewLoaded {
                        let errMsg = "RemoveAppExtensionsOperation: unable to present dialog, view context not available." +
                                     "\nDid you move to different screen or background after starting the operation?"
                        continuation.resume(throwing: OperationError.invalidOperationContext(errMsg))
                    }
                }
            }
        }
        self.setProgress(100)
        return targetAppBundle
    }
    
    private func removeExtensions(from extensions: Set<ALTApplication>, endPercent: Int64) throws {
        let isLoggingEnabled = OperationsLoggingControl.isLoggingEnabled(for: RemoveAppExtensionsOperation.self)
        let startProgress = self.progress.completedUnitCount
        let range = endPercent - startProgress
        guard !extensions.isEmpty else {
            self.setProgress(endPercent)
            return
        }
        let array = Array(extensions)
        let count = array.count
        for (index, appExtension) in array.enumerated() {
            if range > 0 {
                let percent = startProgress + Int64(Double(index + 1) / Double(count) * Double(range))
                self.setProgress(percent)
            }
            if isLoggingEnabled {
                debugLog("Deleting extension \(appExtension.bundleIdentifier)")
            }
            try FileManager.default.removeItem(at: appExtension.fileURL)
        }
    }

    private func updateManifest() throws {
        guard let appBundle = context.targetAppBundle else {
            return
        }
        
        let scInfoURL = appBundle.fileURL.appendingPathComponent("SC_Info")
        let manifestPlistURL = scInfoURL.appendingPathComponent("Manifest.plist")
        
        if let manifestPlist = NSMutableDictionary(contentsOf: manifestPlistURL),
           let sinfReplicationPaths = manifestPlist["SinfReplicationPaths"] as? [String] {
            let replacementPaths = sinfReplicationPaths.filter { !$0.starts(with: "PlugIns/") } // Filter out app extension paths.
            manifestPlist["SinfReplicationPaths"] = replacementPaths
            try manifestPlist.write(to: manifestPlistURL)
        }
    }
    
    struct ExtensionsInfo {
        let excessInTarget: Set<ALTApplication>
        let necessaryInExisting: Set<ALTApplication>
    }
    
    private func processExtensionsInfo(from targetAppBundle: ALTApplication,
                                       localAppExtensions: Set<ALTApplication>?) -> Set<ALTApplication> {
        //App-Extensions: Ensure existing app's extensions in DB and currently installing app bundle's extensions must match
        let targetAppEx: Set<ALTApplication> = targetAppBundle.appExtensions
        let targetAppExNames  = targetAppEx.map { appEx in appEx.bundleIdentifier }

        guard let extensionsInExistingApp = localAppExtensions else {
            let diagnosticsMsg = "RemoveAppExtensionsOperation: ExistingApp is nil, Hence keeping all app extensions from targetAppBundle"
                               + "RemoveAppExtensionsOperation: ExistingAppEx: nil; targetAppBundleEx: \(targetAppExNames)"
            verboseLog(diagnosticsMsg)
            return Set()    // nothing is excess since we are keeping all, so returning empty
        }
        
        let existingAppEx: Set<ALTApplication> = extensionsInExistingApp
        let existingAppExNames = existingAppEx.map { appEx in appEx.bundleIdentifier }
        
        let excessExtensionsInTargetApp = targetAppEx.filter {
            !(existingAppExNames.contains($0.bundleIdentifier))
        }
    
        let isMatching = (targetAppEx.count == existingAppEx.count) && excessExtensionsInTargetApp.isEmpty
        let diagnosticsMsg = "RemoveAppExtensionsOperation: App Extensions in localAppBundle and targetAppBundle are matching: \(isMatching)\n"
                            + "RemoveAppExtensionsOperation: \nlocalAppBundleEx: \(existingAppExNames); \ntargetAppBundleEx: \(String(describing: targetAppExNames))\n"
        verboseLog(diagnosticsMsg)

        return excessExtensionsInTargetApp
    }
}
