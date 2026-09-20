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

    @MainActor
    func presentProtocolMismatchAlert(
        on vc: UIViewController,
        savedPreference: PairingProtocol,
        providedProtocol: PairingProtocol,
        onSwitch: @escaping () -> Void,
        onChooseOther: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let title = NSLocalizedString("Protocol Mismatch", comment: "")
        let message = String(
            format: NSLocalizedString("Your saved preference is %@, but the provided pairing file is %@. Do you want to switch and accept %@ as your current protocol?", comment: ""),
            savedPreference.rawValue,
            providedProtocol.rawValue,
            providedProtocol.rawValue
        )
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(format: NSLocalizedString("Switch to %@", comment: ""), providedProtocol.rawValue), style: .default) { _ in
            onSwitch()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Choose Another File", comment: ""), style: .default) { _ in
            onChooseOther()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            onCancel()
        })
        vc.present(alert, animated: true)
    }

    @MainActor
    func confirmProtocolMismatchSwitch(
        on vc: UIViewController,
        savedPreference: PairingProtocol,
        providedProtocol: PairingProtocol
    ) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            presentProtocolMismatchAlert(
                on: vc,
                savedPreference: savedPreference,
                providedProtocol: providedProtocol,
                onSwitch: {
                    PairingFileManager.shared.preferredProtocol = providedProtocol
                    PairingFileManager.shared.persistedActiveProtocol = providedProtocol
                    continuation.resume(returning: true)
                },
                onChooseOther: {
                    continuation.resume(returning: false)
                },
                onCancel: {
                    continuation.resume(returning: false)
                }
            )
        }
    }

    @MainActor
    func handlePotentialProtocolMismatch(
        on vc: UIViewController,
        pairingContent: String
    ) async -> Bool {
        guard let saved = PairingFileManager.shared.preferredProtocol,
              let parsed = try? PairingFileManager.shared.parse(content: pairingContent, preferred: nil),
              parsed.mode != saved else {
            return false
        }
        return await confirmProtocolMismatchSwitch(
            on: vc,
            savedPreference: saved,
            providedProtocol: parsed.mode
        )
    }
}

#if !os(tvOS)
extension PairingViewController: UIDocumentPickerDelegate {
    @MainActor
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls[0]
        do {
            debugLog("[PairingFile] User picked pairing file from: \(url.path)")
            try PairingFileManager.shared.importPairingFile(from: url)
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
                let activeURL = PairingFileManager.shared.pairingFileURL(for: PairingFileManager.shared.activeProtocol)
                if let completion = self.completion {
                    completion(activeURL)
                } else {
                    Task { @MainActor in
                        do {
                            try await AppBootManager.shared.startMinimuxer(pairingFile: pairingString)
                        } catch {
                            debugLog("[PairingFile] startMinimuxer failed: \(error)")
                            if await self.handlePotentialProtocolMismatch(on: vc, pairingContent: pairingString) {
                                do {
                                    try await AppBootManager.shared.startMinimuxer(pairingFile: pairingString)
                                } catch {
                                    debugLog("[PairingFile] startMinimuxer retry after protocol switch failed: \(error)")
                                }
                            }
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
