//
//  ImportExport.swift
//  SideStore
//
//  Created by Magesh K on 07/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


@preconcurrency import UIKit
@preconcurrency import AltSign
@preconcurrency import AltStoreCore
import CryptoKit
import CommonCrypto

enum BackupEncryptionError: Error, LocalizedError {
    case invalidPassword
    case decryptionFailed
    case exportPasswordMatchesApplePassword
    
    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return "Invalid password."
        case .decryptionFailed:
            return "Incorrect password or corrupted backup file."
        case .exportPasswordMatchesApplePassword:
            return "File password cannot be the same as Apple ID password stored in secure keychain."
        }
    }
}

class ImportExport {
    
    public static var documentPickerHandler: DocumentPickerHandler?

    public static func exportAccountJSON(password: String) -> ImportedAccount? {
        guard let email = AuthManager.shared.currentAppleID,
              let passwordStr = AuthManager.shared.password,
              let cert = CertificateManager.shared.activeSigningCertificateData,
              let identifier = Keychain.shared.identifier,
              let adiPB = Keychain.shared.adiPb else {
            return nil
        }
        return ImportedAccount(email: email, password: passwordStr, certificateData: cert, certificatePassword: password, anisetteIdentifier: identifier, anisetteAdiBlob: adiPB)
    }

    public static func importAccountJSON(from file: URL) throws {
        _ = file.startAccessingSecurityScopedResource()
        defer { file.stopAccessingSecurityScopedResource() }
        
        let accountData = try Data(contentsOf: file)
        let account = try Foundation.JSONDecoder().decode(ImportedAccount.self, from: accountData)
        
        Keychain.shared.reset()
        AuthManager.shared.currentAppleID = account.email
        AuthManager.shared.password = account.password
        Keychain.shared.adiPb = account.anisetteAdiBlob
        Keychain.shared.identifier = account.anisetteIdentifier
        
        let altCert = try ALTCertificate(p12Data: account.certificateData, password: account.certificatePassword)
        CertificateManager.shared.activeCertificate = altCert
    }

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derivedKeyData = Data(count: 32)
        
        _ = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        10000,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        return SymmetricKey(data: derivedKeyData)
    }

    public static func exportAccount(password: String, includeApplePassword: Bool) throws -> Data {
        guard let email = AuthManager.shared.currentAppleID,
              let cert = CertificateManager.shared.activeSigningCertificateData,
              let identifier = Keychain.shared.identifier,
              let adiPB = Keychain.shared.adiPb else {
            throw OperationError.invalidParameters("Account or signing data is missing.")
        }
        
        if let applePass = AuthManager.shared.password, password == applePass {
            throw BackupEncryptionError.exportPasswordMatchesApplePassword
        }

        let applePasswordToInclude = includeApplePassword ? AuthManager.shared.password : nil
        let account = ImportedAccount(email: email, password: applePasswordToInclude, certificateData: cert, certificatePassword: password, anisetteIdentifier: identifier, anisetteAdiBlob: adiPB)

        let jsonData = try Foundation.JSONEncoder().encode(account)
        
        var salt = Data(count: 16)
        let result = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard result == errSecSuccess else {
            throw OperationError.invalidParameters("Failed to generate random salt.")
        }
        
        let key = deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        guard let combined = sealedBox.combined else {
            throw OperationError.invalidParameters("Encryption failed.")
        }
        
        var finalData = Data()
        finalData.append(salt)
        finalData.append(combined)
        return finalData
    }

    public static func importAccountData(_ encryptedData: Data, filePassword: String) throws -> ImportedAccount {
        guard encryptedData.count > 16 else {
            throw BackupEncryptionError.decryptionFailed
        }
        
        let salt = encryptedData.prefix(16)
        let gcmData = encryptedData.dropFirst(16)
        
        let key = deriveKey(password: filePassword, salt: salt)
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: gcmData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let account = try Foundation.JSONDecoder().decode(ImportedAccount.self, from: decryptedData)
            
            Keychain.shared.reset()
            AuthManager.shared.currentAppleID = account.email
            if let pass = account.password, !pass.isEmpty {
                AuthManager.shared.password = pass
            }
            Keychain.shared.adiPb = account.anisetteAdiBlob
            Keychain.shared.identifier = account.anisetteIdentifier
            
            let altCert = try ALTCertificate(p12Data: account.certificateData, password: account.certificatePassword)
            CertificateManager.shared.activeCertificate = altCert
            
            return account
        } catch {
            throw BackupEncryptionError.decryptionFailed
        }
    }
    
    public static func getPreviousBackupURL(_ backupURL: URL) -> URL {
        let backupParentDirectory = backupURL.deletingLastPathComponent()
        let backupName = backupURL.lastPathComponent
        let backupBakURL = backupParentDirectory.appendingPathComponent("\(backupName).bak")
        return backupBakURL
    }
    
    /// Renames the existing backup contents at `backupURL` to `<foldername>.bak`.
    private static func renameBackupContents(at backupURL: URL) throws {
        
        // rename backup to backup.bak dir only if backup dir exists
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        
        let backupBakURL = getPreviousBackupURL(backupURL)
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: backupBakURL.path) {
            try fileManager.removeItem(at: backupBakURL) // Remove any existing .bak directory
        }
        
        try fileManager.moveItem(at: backupURL, to: backupBakURL)
    }
    
    /// Handles importing new backup data into the designated backup directory.
    private static func importBackupContents(from documentPickerURL: URL, to backupURL: URL) throws {
        let fileManager = FileManager.default
        
        // Ensure the backup directory exists.
        if !fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        debugLog("Backup URL: \(backupURL)")
        debugLog("Document Picker URL: \(documentPickerURL)")
        
        // Enumerate the contents of the selected directory and copy them to the backup directory.
        let selectedContents = try fileManager.contentsOfDirectory(
            at: documentPickerURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        for itemURL in selectedContents {
            let destinationURL = backupURL.appendingPathComponent(itemURL.lastPathComponent)
            
            // Remove the existing file if it exists at the destination.
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Copy the item.
            try fileManager.copyItem(at: itemURL, to: destinationURL)
        }
    }
    
    public static func importBackup(presentingViewController: UIViewController,
                                    for installedApp: InstalledApp,
                                    completionHandler: @escaping (Result<Void, Error>) -> Void){
        guard let backupURL = FileManager.default.backupDirectoryURL(for: installedApp) else {
            return completionHandler(.failure(OperationError.invalidParameters("Error: Backup directory URL not found.")))
        }
        
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        documentPicker.allowsMultipleSelection = false
                
        // Create a handler and set it as the delegate
        Self.documentPickerHandler = DocumentPickerHandler { selectedURL in
            guard let selectedURL = selectedURL else {
                return completionHandler(.failure( OperationError.cancelled))
            }
            
            // resolve symlinks if any, so that prefix match works
            let appUserDataDir = FileManager.default.documentsDirectory.resolvingSymlinksInPath()
            guard selectedURL.resolvingSymlinksInPath().path.hasPrefix(appUserDataDir.path) else {
                return completionHandler(.failure(
                    OperationError.forbidden(failureReason: "Selected backup data directory is not within the app's user data directory"))
                )
            }
            
            do {
                // Rename existing backup contents to `<foldername>.bak`.
                try Self.renameBackupContents(at: backupURL)
                
                // Import the contents of the selected folder into the backup directory.
                try Self.importBackupContents(from: selectedURL, to: backupURL)
                
                debugLog("Backup imported successfully to: \(backupURL.path)")
                return completionHandler(.success(()))
            } catch {
                debugLog("Backup Error: \(error)")
                return completionHandler(.failure( OperationError.invalidParameters(error.localizedDescription)))
            }
        }
        
        documentPicker.delegate = Self.documentPickerHandler
        // Present the picker
        presentingViewController.present(documentPicker, animated: true, completion: nil)
    }
}

private struct AssociatedKeys {
    static var documentPickerHandler = "documentPickerHandler"
}


class DocumentPickerHandler: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}
