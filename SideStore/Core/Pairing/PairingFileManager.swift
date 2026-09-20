//
//  PairingFileManager.swift
//  SideStore
//
//  Created by Magesh K on 17/06/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers
import MinimuxerCommon

public struct PairingFileMetadata: Sendable {
    public let exists: Bool
    public let size: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
}

final class PairingFileManager: NSObject {
    static let shared = PairingFileManager()

    static var supportedContentTypes: [UTType] {
        var types = AppConstants.Pairing.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        types.append(contentsOf: [.propertyList, .xml])
        return types
    }

    var activeProtocol: PairingProtocol {
        minimuxerPairingProtocol()
    }

    var persistedActiveProtocol: PairingProtocol? {
        get { UserDefaults.standard.activePairingProtocol }
        set { UserDefaults.standard.activePairingProtocol = newValue }
    }

    var preferredProtocol: PairingProtocol? {
        get { UserDefaults.standard.preferredPairingProtocol }
        set { UserDefaults.standard.preferredPairingProtocol = newValue }
    }

    nonisolated func pairingFileURL(for mode: PairingProtocol) -> URL {
        let fileName = mode == .rppairing ? AppConstants.Pairing.remotePairingFileName : AppConstants.Pairing.lockdownPairingFileName
        return FileManager.default.documentsDirectory.appendingPathComponent(fileName)
    }

    nonisolated func hasPairingFile(for mode: PairingProtocol) -> Bool {
        return FileManager.default.fileExists(atPath: pairingFileURL(for: mode).path)
    }

    nonisolated func hasPairingFile() -> Bool {
        guard !UserDefaults.standard.isPairingReset else { return false }
        return hasPairingFile(for: UserDefaults.standard.activePairingFileType)
    }

    nonisolated func metadata(for mode: PairingProtocol) -> PairingFileMetadata {
        let fileURL = pairingFileURL(for: mode)
        let path = fileURL.path
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return PairingFileMetadata(exists: false, size: 0, creationDate: nil, modificationDate: nil)
        }
        let attrs = (try? fm.attributesOfItem(atPath: path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let creation = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date)
        let mod = attrs[.modificationDate] as? Date
        return PairingFileMetadata(exists: true, size: size, creationDate: creation, modificationDate: mod)
    }

    nonisolated func fetchPairingFile(for mode: PairingProtocol) -> String? {
        let fileURL = pairingFileURL(for: mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path),
           let contents = try? String(contentsOf: fileURL), !contents.isEmpty 
        {
            return contents
        }
        return nil
    }

    nonisolated func fetchPairingFile() -> String? {
        guard !UserDefaults.standard.isPairingReset else { return nil }
        let activeType = UserDefaults.standard.activePairingFileType
        if let activeContent = fetchPairingFile(for: activeType), !activeContent.isEmpty 
        {
            return activeContent
        }
        return nil
    }

    nonisolated static func parsePairingTypes(content: String) -> (rp: RPPairingFile?, lockdown: LockdownPairingFile?) {
        guard let data = content.data(using: .utf8),
              let rawDict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return (nil, nil)
        }
        let plist = ConcurrencyUtils.toSendableDictionary(rawDict)
        let rp = try? RPPairingFile(content: content, plist: plist, data: data)
        let lockdown = try? LockdownPairingFile(content: content, plist: plist, data: data)
        return (rp, lockdown)
    }

    func savePairingFile(contents: String) throws {
        let (rp, lockdown) = Self.parsePairingTypes(content: contents)
        if rp != nil {
            try contents.write(to: pairingFileURL(for: .rppairing), atomically: true, encoding: .utf8)
        }
        if lockdown != nil {
            try contents.write(to: pairingFileURL(for: .lockdown), atomically: true, encoding: .utf8)
        }

        debugLog("[PairingFile] Successfully saved pairing file(s)")
        UserDefaults.standard.isPairingReset = false
    }

    func savePairingFile(contents: String, for mode: PairingProtocol) throws {
        let fileURL = pairingFileURL(for: mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: fileURL)
        }
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        debugLog("[PairingFile] Saved \(mode.rawValue) pairing file to: \(fileURL.path)")
        UserDefaults.standard.isPairingReset = false
    }

    func importPairingFile(from url: URL, for mode: PairingProtocol? = nil) throws {
        let isSecured = url.startAccessingSecurityScopedResource()
        defer {
            if isSecured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        if let mode = mode {
            try savePairingFile(contents: content, for: mode)
            activeProtocol = mode
        } else {
            try savePairingFile(contents: content)
        }
    }

    func deletePairingFile(for mode: PairingProtocol) {
        let fileURL = pairingFileURL(for: mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: fileURL)
            debugLog("[PairingFile] Deleted \(mode.rawValue) pairing file: \(fileURL.path)")
        }
        if mode == activeProtocol {
            let other: PairingProtocol = (mode == .rppairing) ? .lockdown : .rppairing
            if hasPairingFile(for: other) {
                activeProtocol = other
            }
        }
    }

    func resetAllPairingFiles() {
        let fm = FileManager.default
        let files = [
            AppConstants.Pairing.lockdownPairingFileName,
            AppConstants.Pairing.remotePairingFileName,
            AppConstants.Pairing.legacyPairingFileName
        ]
        for name in files {
            let path = fm.documentsDirectory.appendingPathComponent(name)
            if fm.fileExists(atPath: path.path) {
                try? fm.removeItem(at: path)
            }
        }
        UserDefaults.standard.isPairingReset = true
        debugLog("[PairingFile] Reset all pairing files.")
    }
}
