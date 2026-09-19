//
//  PairingViewController.swift
//  SideStore
//
//  Created by Magesh K on 20/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers
import MinimuxerCommon

final class PairingViewController: NSObject {
    static let shared = PairingViewController()

    private var completion: ((URL?) -> Void)?

    @MainActor
    func presentPairingFileAlert(on vc: UIViewController, isRetry: Bool, completion: ((URL?) -> Void)? = nil) {
        self.completion = { url in
            completion?(url)
            self.completion = nil
        }
        let title = isRetry ? NSLocalizedString("Invalid Pairing File", comment: "") : NSLocalizedString("Pairing File", comment: "")
        let message = isRetry
            ? NSLocalizedString("The selected pairing file is invalid or not usable. Please select a valid pairing file.", comment: "")
            : NSLocalizedString("Select the pairing file or select \"Help\" for help.", comment: "")
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Help", comment: ""), style: .default) { _ in
            UIApplication.shared.open(AppConstants.URLs.pairingDocumentation)
            if completion == nil {
                sleep(2); exit(0)
            } else {
                completion?(nil)
            }
        })
        #if !os(tvOS)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Select File", comment: ""), style: .default) { _ in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: PairingFileManager.supportedContentTypes)
            picker.delegate = self
            picker.shouldShowFileExtensions = true
            vc.present(picker, animated: true)
            UserDefaults.standard.isPairingReset = false
        })
        #endif
        
        let cancelTitle = isRetry ? NSLocalizedString("Skip", comment: "") : NSLocalizedString("Cancel", comment: "")
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
            if completion == nil {
                self.showPairingWarningAndProceed(on: vc)
            } else {
                completion?(nil)
            }
        })
        vc.present(alert, animated: true)
    }

    func showPairingWarningAndProceed(on vc: UIViewController) {
        let warningAlert = UIAlertController(
            title: "⚠️ " + NSLocalizedString("Pairing Required", comment: ""),
            message: NSLocalizedString("Without a valid pairing file, operations that require a pairing file (such as installing, refreshing, or resigning apps) will not function.", comment: ""),
            preferredStyle: .alert
        )
        warningAlert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        vc.present(warningAlert, animated: true)
    }

    func importPairingFile(presentingVC: UIViewController, title: String, message: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.presentPairingFileAlert(on: presentingVC, isRetry: false) { url in
                    if let url = url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: OperationError.cancelled)
                    }
                }
            }
        }
    }
}

#if !os(tvOS)
extension PairingViewController: UIDocumentPickerDelegate {
    @MainActor
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls[0]
        let isSecuredURL = url.startAccessingSecurityScopedResource() == true
        defer {
            if isSecuredURL {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            debugLog("[PairingFile] User picked pairing file from: \(url.path)")
            let data = try Data(contentsOf: url)
            guard let pairingString = String(data: data, encoding: .utf8) else {
                debugLog("[PairingFile] Unable to read pairing file")
                self.completion?(nil)
                return
            }
            try PairingFileManager.shared.savePairingFile(contents: pairingString)
            self.completion?(url)
        } catch {
            debugLog("[PairingFile] Error importing pairing file: \(error)")
            self.completion?(nil)
        }

        controller.dismiss(animated: true, completion: nil)
    }

    @MainActor
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion?(nil)
    }
}
#else
extension PairingViewController {
    @MainActor
    func startTVImport(on vc: UIViewController, isRetry: Bool, completion: ((URL?) -> Void)? = nil) {
        self.completion = { url in
            completion?(url)
            self.completion = nil
        }

        let title = isRetry ? NSLocalizedString("Invalid Pairing File", comment: "") : NSLocalizedString("Pairing File Required", comment: "")
        TVWebFileTransferManager.shared.startImport(
            acceptedExtensions: AppConstants.Pairing.supportedExtensions,
            title: title,
            presentingVC: vc
        ) { [weak self] tempURL in
            guard let self = self else { return }
            guard let tempURL = tempURL,
                  let data = try? Data(contentsOf: tempURL),
                  let pairingString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                if let completion = self.completion {
                    completion(nil)
                } else {
                    self.showPairingWarningAndProceed(on: vc)
                }
                return
            }

            do {
                try PairingFileManager.shared.savePairingFile(contents: pairingString)
                let documentsPath = FileManager.default.documentsDirectory.appendingPathComponent(AppConstants.Pairing.legacyPairingFileName)
                if let completion = self.completion {
                    completion(documentsPath)
                } else {
                    Task.detached {
                        do {
                            try await AppBootManager.shared.startMinimuxer(pairingFile: pairingString)
                        } catch {
                            debugLog("[PairingFile] startMinimuxer failed: \(error)")
                        }
                    }
                }
            } catch {
                debugLog("[PairingFile] Failed to save uploaded pairing file: \(error)")
                if let completion = self.completion {
                    completion(nil)
                }
            }
        }
    }
}
#endif
