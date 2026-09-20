//
//  PairingFileManagementViewModel.swift
//  SideStore
//
//  Created by Magesh K on 20/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers
import MinimuxerCommon

@MainActor
public final class PairingFileManagementViewModel: ObservableObject {
    public enum ActiveAlert: Identifiable {
        case deleteConfirmation(PairingProtocol)
        case resetConfirmation
        case resetCompleted
        case importError(String)
        case protocolMismatch(saved: PairingProtocol, provided: PairingProtocol, url: URL)

        public var id: String {
            switch self {
            case .deleteConfirmation(let p): return "delete_\(p.rawValue)"
            case .resetConfirmation: return "reset"
            case .resetCompleted: return "resetCompleted"
            case .importError(let msg): return "importError_\(msg)"
            case .protocolMismatch(let saved, let provided, _): return "mismatch_\(saved.rawValue)_\(provided.rawValue)"
            }
        }
    }

    @Published public var activeProtocol: PairingProtocol = .unknown
    @Published public var preferredProtocol: PairingProtocol? = nil
    @Published public var isGlobalHideActive: Bool = true
    @Published public var revealedFieldKeys: Set<String> = []
    @Published public var showFileImporter: Bool = false
    @Published public var targetImportMode: PairingProtocol? = nil
    @Published public var activeAlert: ActiveAlert? = nil
    @Published public var isActivating: Bool = false

    public let supportedProtocols: [PairingProtocol] = [.lockdown, .rppairing]

    public var allowedPairingTypes: [UTType] {
        PairingFileManager.supportedContentTypes
    }

    public init() {
        refresh()
    }

    public func refresh() {
        activeProtocol = PairingFileManager.shared.activeProtocol
        preferredProtocol = PairingFileManager.shared.preferredProtocol
    }

    public func toggleGlobalHide() {
        isGlobalHideActive.toggle()
        if isGlobalHideActive {
            revealedFieldKeys.removeAll()
        }
    }

    public func toggleReveal(for fieldKey: String) {
        if revealedFieldKeys.contains(fieldKey) {
            revealedFieldKeys.remove(fieldKey)
        } else {
            revealedFieldKeys.insert(fieldKey)
        }
    }

    public func promptImport(for mode: PairingProtocol) {
        targetImportMode = mode
        showFileImporter = true
    }

    public func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard let (_, parsed) = try? PairingFileManager.shared.inspectPairingFile(from: url) else {
                do {
                    try PairingFileManager.shared.importPairingFile(from: url, preferred: targetImportMode)
                    targetImportMode = nil
                    refresh()
                } catch {
                    activeAlert = .importError("Failed to import pairing file: \(error.localizedDescription)")
                }
                return
            }

            let savedPref = preferredProtocol ?? targetImportMode
            if let saved = savedPref, parsed.mode != saved {
                activeAlert = .protocolMismatch(saved: saved, provided: parsed.mode, url: url)
                return
            }

            do {
                try PairingFileManager.shared.importPairingFile(from: url, preferred: parsed.mode)
                targetImportMode = nil
                refresh()
            } catch {
                activeAlert = .importError("Failed to import pairing file: \(error.localizedDescription)")
            }
        case .failure(let error):
            activeAlert = .importError(error.localizedDescription)
        }
    }

    public func confirmProtocolMismatch(url: URL, newProtocol: PairingProtocol) {
        do {
            PairingFileManager.shared.preferredProtocol = newProtocol
            try PairingFileManager.shared.importPairingFile(from: url, preferred: newProtocol)
            targetImportMode = nil
            refresh()
        } catch {
            activeAlert = .importError("Failed to import pairing file: \(error.localizedDescription)")
        }
    }

    public func activate(proto: PairingProtocol) async {
        isActivating = true
        defer { isActivating = false }
        do {
            try await minimuxerSwitchPairingProtocol(to: proto)
            refresh()
        } catch {
            debugLog("[PairingFileManagementViewModel] Failed to activate \(proto.rawValue): \(error)")
            activeAlert = .importError("Failed to activate \(proto.rawValue): \(error.localizedDescription)")
            refresh()
        }
    }

    public func setPreferred(proto: PairingProtocol) {
        PairingFileManager.shared.preferredProtocol = proto
        refresh()
    }

    public func clearPreferred() {
        PairingFileManager.shared.preferredProtocol = nil
        refresh()
    }

    public func confirmDelete(for proto: PairingProtocol) {
        activeAlert = .deleteConfirmation(proto)
    }

    public func deletePairingFile(for proto: PairingProtocol) {
        PairingFileManager.shared.deletePairingFile(for: proto)
        refresh()
    }

    public func confirmReset() {
        activeAlert = .resetConfirmation
    }

    public func resetAllPairingFiles() {
        PairingFileManager.shared.resetAllPairingFiles()
        refresh()
        activeAlert = .resetCompleted
    }
}
