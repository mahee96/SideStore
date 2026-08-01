//
//  UserCustomizationOperation.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltStoreCore
final class UserCustomizationOperation: BasePipelineOperation<InstallAppOperationContext, String?>, @unchecked Sendable {

    override func execute(parentProgress: Progress?) async throws -> String? {
        debugLog("[UserCustomizationOperation] execute() started")
        defer { debugLog("[UserCustomizationOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        guard UserDefaults.standard.customizeAppId else {
            self.setProgress(100)
            return nil
        }

        guard let presentingVC = context.authenticatedContext.presentingViewController else {
            self.setProgress(100)
            return context.targetBundleIdentifier
        }

        let initialBundleID = context.targetBundleIdentifier
        self.setProgress(40)
        let resolution: BundleIDResolution = try await makeBundleIDOverrideAlert(
            initialBundleID: initialBundleID,
            presentingVC: presentingVC
        )

        switch resolution {
        case .resolved(let customID):
            if customID != context.bundleIdentifier {
                context.customBundleIdentifier = customID
            }
        case .cancelled:
            throw OperationError.cancelled
        }
        self.setProgress(100)
        return context.targetBundleIdentifier
    }

    enum BundleIDResolution {
        case resolved(String)
        case cancelled
    }

    @MainActor
    private func makeBundleIDOverrideAlert(
        initialBundleID: String,
        presentingVC: UIViewController) async throws -> BundleIDResolution
    {
        let titleText = NSLocalizedString("AppID Customization", comment: "")
        let messageText = NSLocalizedString("Customize the AppID if required and press 'Confirm' to proceed.", comment: "")

        let alert = UIAlertController(
            title: titleText,
            message: messageText,
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.text = initialBundleID
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.addTarget(
                self,
                action: #selector(self.isValidBundleId(_:)),
                for: .editingChanged
            )
        }

        return await withCheckedContinuation { continuation in
            let okAction = UIAlertAction(title: NSLocalizedString("Confirm", comment: ""), style: .default) { _ in
                continuation.resume(returning: .resolved(alert.textFields?.first?.text ?? initialBundleID))
            }
            okAction.isEnabled = self.bundleIdChecker(initialBundleID)
            
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                continuation.resume(returning: .cancelled)
            }
            alert.addAction(cancelAction)
            alert.addAction(okAction)
            presentingVC.present(alert, animated: true)
        }
    }
    
    private func bundleIdChecker(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        let pattern = "^[a-zA-Z0-9.-]+$"
        return bundleID.range(of: pattern, options: .regularExpression) != nil
    }

    @objc func isValidBundleId(_ sender: UITextField) {
        let text = sender.text ?? ""
        let isValid = self.bundleIdChecker(text)

        sender.backgroundColor = (isValid || text.isEmpty)
            ? .clear
            : UIColor.systemRed.withAlphaComponent(0.2)

        if let alert = sender.superview?.superview as? UIAlertController,
           let okAction = alert.actions.first(where: { $0.style == .default })
        {
            okAction.isEnabled = isValid
        }
    }
}
