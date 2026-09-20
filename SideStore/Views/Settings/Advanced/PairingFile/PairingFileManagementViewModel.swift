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

        public var id: String {
            switch self {
            case .deleteConfirmation(let p): return "delete_\(p.rawValue)"
            case .resetConfirmation: return "reset"
            case .resetCompleted: return "resetCompleted"
            case .importError(let msg): return "importError_\(msg)"
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
            do {
                try PairingFileManager.shared.importPairingFile(from: url, for: targetImportMode)
                refresh()
            } catch {
                activeAlert = .importError("Failed to import pairing file: \(error.localizedDescription)")
            }
        case .failure(let error):
            activeAlert = .importError(error.localizedDescription)
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
