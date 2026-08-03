//
//  PreflightChecksOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class PreflightChecksOperation: BasePipelineOperation<AuthenticatedOperationContext, Bool>, @unchecked Sendable {
    let operations: [AppOperation]
    let presentingViewController: UIViewController?

    init(operations: [AppOperation], presentingViewController: UIViewController?, context: AuthenticatedOperationContext) throws {
        self.operations = operations
        self.presentingViewController = presentingViewController
        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?) async throws -> Bool {
        debugLog("[PreflightChecksOperation] execute() started")
        defer { debugLog("[PreflightChecksOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        let currentTeam = self.context.team ?? AuthManager.shared.team
        let currentTeamID = currentTeam?.identifier

        let startProgress = self.progress.completedUnitCount
        let endProgress: Int64 = 90
        let range = endProgress - startProgress
        let count = operations.count
        
        for (index, operation) in operations.enumerated() {
            if range > 0 {
                let percent = startProgress + Int64(Double(index + 1) / Double(count) * Double(range))
                self.setProgress(percent)
            }
            
            let isSideStore = (operation.app as? ALTApplication)?.isAltStoreApp == true ||
                               operation.bundleIdentifier.contains(ALTApplication.altstoreBundleID) ||
                               operation.bundleIdentifier == StoreApp.altstoreAppID
            guard isSideStore else { continue }
            guard let installedApp = operation.app as? InstalledApp else { continue }

            let activeResignedID = installedApp.resignedBundleIdentifier
            let activeEffectiveID = installedApp.customBundleIdentifier ?? activeResignedID

            let incomingTargetID: String?
            switch operation {
                case .install(let app, let customBundleIdentifier), .update(let app, let customBundleIdentifier):
                    if let customBundleIdentifier = customBundleIdentifier, !customBundleIdentifier.isEmpty {
                        incomingTargetID = customBundleIdentifier
                    } else if let currentTeamID = currentTeamID {
                        incomingTargetID = "\(StoreApp.altstoreAppID).\(currentTeamID)"
                    } else if let installedApp = app as? InstalledApp {
                        incomingTargetID = installedApp.customBundleIdentifier ?? installedApp.resignedBundleIdentifier
                    } else {
                        incomingTargetID = nil
                    }
                case .refresh(let installedApp),    .activate(let installedApp),    .deactivate(let installedApp), .deleteApp(let installedApp),
                     .backup(let installedApp),     .restore(let installedApp),     .resign(let installedApp, _),
                     .removeDeactivatedApp(let installedApp),     .enableJIT(let installedApp):
                    
                    if let currentTeamID = currentTeamID, installedApp.bundleIdentifier == StoreApp.altstoreAppID {
                        incomingTargetID = installedApp.customBundleIdentifier ?? "\(StoreApp.altstoreAppID).\(currentTeamID)"
                    } else {
                        incomingTargetID = installedApp.customBundleIdentifier ?? installedApp.resignedBundleIdentifier
                    }
            }

            guard let targetID = incomingTargetID, targetID != activeEffectiveID && targetID != activeResignedID else { continue }

            debugLog("[PreflightChecksOperation] SideStore bundle ID mismatch detected: target='\(targetID)', active='\(activeEffectiveID)'")

            switch operation {
                case .resign, .install:
                    var presenter = await MainActor.run{
                        var presenter = presentingViewController ?? UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .flatMap({ $0.windows })
                            .first(where: { $0.isKeyWindow })?.rootViewController
                        while let presented = presenter?.presentedViewController, !presented.isBeingDismissed {
                            presenter = presented
                        }
                        return presenter
                    }
                    
                    let shouldContinue = await presentAlertDialog(
                        presenter: presenter,
                        targetID: targetID,
                        activeEffectiveID: activeEffectiveID
                    )

                    if !shouldContinue {
                        debugLog("[PreflightChecksOperation] SideStore bundle ID mismatch prompt cancelled by user. Throwing OperationError.cancelled.")
                        throw OperationError.cancelled
                    }

                default: continue
            }
        }
        self.setProgress(100)
        return true
    }
    
    @MainActor
    private func presentAlertDialog(presenter: UIViewController?, targetID: String, activeEffectiveID: String) async -> Bool {
        guard let presenter = presenter else {
            return false
        }
        
        debugLog("[ValidateSideStoreBundleIDOperation] Presenting SideStore bundle ID mismatch alert modal (target='\(targetID)', active='\(activeEffectiveID)')...")
        
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: NSLocalizedString("Bundle ID Mismatch Detected", comment: ""),
                message: String(format: NSLocalizedString("The target bundle ID '%@' does not match the active SideStore instance ('%@').\n\nProceeding will install a new instance of SideStore instead of updating the current instance.", comment: ""), targetID, activeEffectiveID),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                self.debugLog("[ValidateSideStoreBundleIDOperation] User tapped Cancel on SideStore bundle ID mismatch alert modal.")
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .destructive) { _ in
                self.debugLog("[ValidateSideStoreBundleIDOperation] User tapped Continue on SideStore bundle ID mismatch alert modal.")
                continuation.resume(returning: true)
            })
            presenter.present(alert, animated: true)
        }
    }
}
