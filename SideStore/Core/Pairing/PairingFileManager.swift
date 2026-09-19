//
//  PairingFileManager.swift
//  SideStore
//
//  Created by Magesh K on 17/06/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import MinimuxerCommon

final class PairingFileManager: NSObject {
    static let shared = PairingFileManager()
    static let legacyPairingFileName = AppConstants.Pairing.legacyPairingFileName

    nonisolated var pairingUDID: String? {
        guard let contents = fetchPairingFile() else {
            debugLog("[PairingFile] pairingUDID: fetchPairingFile() returned nil")
            return nil
        }
        return (try? PairingFileParser.parse(content: contents) as? LockdownPairingFile)?.udid
    }

    nonisolated func pairingFileURL(for mode: PairingProtocol) -> URL {
        let fileName = mode == .rppairing ? AppConstants.Pairing.remotePairingFileName : AppConstants.Pairing.lockdownPairingFileName
        return FileManager.default.documentsDirectory.appendingPathComponent(fileName)
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
        let fm = FileManager.default
        let legacyPath = fm.documentsDirectory.appendingPathComponent(Self.legacyPairingFileName)
        if fm.fileExists(atPath: legacyPath.path) {
            try? fm.removeItem(at: legacyPath)
        }
        try contents.write(to: legacyPath, atomically: true, encoding: .utf8)

        let (rp, lockdown) = Self.parsePairingTypes(content: contents)
        if rp != nil {
            try? contents.write(to: pairingFileURL(for: .rppairing), atomically: true, encoding: .utf8)
        }
        if lockdown != nil {
            try? contents.write(to: pairingFileURL(for: .lockdown), atomically: true, encoding: .utf8)
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

    func deletePairingFile(for mode: PairingProtocol) {
        let fileURL = pairingFileURL(for: mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: fileURL)
            debugLog("[PairingFile] Deleted \(mode.rawValue) pairing file: \(fileURL.path)")
        }
    }
}
