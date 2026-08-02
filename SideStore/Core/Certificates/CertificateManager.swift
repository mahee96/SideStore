//
//  CertificateManager.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import KeychainAccess
@preconcurrency import AltSign

public struct ActiveCertificate: Sendable {
    public let certificate: ALTCertificate
    public let p12Data: Data
    public let password: String?
    
    public var serialNumber: String {
        certificate.serialNumber
    }

    fileprivate init(certificate: ALTCertificate, p12Data: Data, password: String?) {
        self.certificate = certificate
        self.p12Data = p12Data
        self.password = password
    }
}

public final class CertificateManager: @unchecked Sendable {
    public static let shared = CertificateManager()
    
    private let keychain = KeychainAccess.Keychain(service: Bundle.Info.appbundleIdentifier)
        .accessibility(.afterFirstUnlock)
        .synchronizable(true)
        
    private let serialsKey = "importedCertificateSerials"
    private let metadataPrefix = "certMetadata_"
    private let certKeyPrefix = "importedCert_"
    
    public private(set) var activeCertificate: ActiveCertificate?
    
    private init() {
        try? loadActiveCertificate()
    }
    
    // MARK: - Active Keychain Certificate Encapsulation
    
    /// Loads active signing certificate from Keychain into memory.
    @discardableResult
    public func loadActiveCertificate() throws -> ActiveCertificate? {
        guard let data = Keychain.shared.signingCertificate else {
            debugLog("[CertificateManager] loadActiveCertificate: No signingCertificate data found in Keychain.")
            self.activeCertificate = nil
            return nil
        }
        let password = Keychain.shared.signingCertificatePassword
        do {
            let cert = try CertificateStore.load(data, password: password)
            let active = ActiveCertificate(certificate: cert, p12Data: data, password: password)
            self.activeCertificate = active
            debugLog("[CertificateManager] loadActiveCertificate: Successfully loaded certificate (serial: \(cert.serialNumber)).")
            return active
        } catch {
            debugLog("[CertificateManager] loadActiveCertificate failed to load/decrypt certificate: \(error)")
            self.activeCertificate = nil
            throw error
        }
    }

    /// Sets active signing certificate in memory cache, encrypts and persists to Keychain.
    public func setActiveCertificate(_ cert: ALTCertificate?) throws {
        if let cert = cert {
            do {
                let p12Data = try CertificateStore.export(cert, password: cert.machineIdentifier)
                Keychain.shared.signingCertificate = p12Data
                Keychain.shared.signingCertificatePassword = cert.machineIdentifier
                saveCertificate(cert)
                let active = ActiveCertificate(certificate: cert, p12Data: p12Data, password: cert.machineIdentifier)
                self.activeCertificate = active
                debugLog("[CertificateManager] setActiveCertificate: Successfully stored certificate (serial: \(cert.serialNumber)).")
            } catch {
                debugLog("[CertificateManager] setActiveCertificate failed to export/encrypt certificate: \(error)")
                throw error
            }
        } else {
            self.activeCertificate = nil
            Keychain.shared.signingCertificate = nil
            Keychain.shared.signingCertificatePassword = nil
            debugLog("[CertificateManager] setActiveCertificate: Cleared active certificate in Keychain.")
        }
    }

    /// Clears active certificate in memory cache and Keychain.
    public func clearActiveCertificate() throws {
        debugLog("[CertificateManager] clearActiveCertificate: Clearing active certificate.")
        try setActiveCertificate(nil)
    }
    
    // MARK: - Certificate Encoding Helpers
    
    public var activeSigningCertificateBase64Encoded: String? {
        guard let data = activeSigningCertificateData else { return nil }
        let base64 = data.base64EncodedString()
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ";/?:@&=+$, ")
        return base64.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    public func saveCertificate(_ cert: ALTCertificate) {
        debugLog("[CertificateManager] saveCertificate started for serial: \(cert.serialNumber)")
        defer { debugLog("[CertificateManager] saveCertificate completed for serial: \(cert.serialNumber)") }
        
        if cert.privateKey != nil {
            do {
                let p12Data = try CertificateStore.export(cert, password: cert.machineIdentifier)
                debugLog("[CertificateManager] p12Data generated, size: \(p12Data.count)")
                try self.keychain.set(p12Data, key: certKeyPrefix + cert.serialNumber)
                debugLog("[CertificateManager] Successfully saved p12 to keychain")
            } catch {
                debugLog("[CertificateManager] Failed to export/save p12 to keychain: \(error)")
            }
        } else if let derData = cert.data {
            debugLog("[CertificateManager] derData exists, size: \(derData.count)")
            do {
                try self.keychain.set(derData, key: certKeyPrefix + cert.serialNumber)
                debugLog("[CertificateManager] Successfully saved der to keychain")
            } catch {
                debugLog("[CertificateManager] Failed to save der to keychain: \(error)")
            }
        }
        
        let serials = getImportedCertificateSerials()
        if !serials.contains(cert.serialNumber) {
            var updatedSerials = serials
            updatedSerials.append(cert.serialNumber)
            setImportedCertificateSerials(updatedSerials)
        }
        
        var metadataDict: [String: String] = [
            "name": cert.name,
            "serialNumber": cert.serialNumber,
            "hasPrivateKey": cert.privateKey != nil ? "true" : "false"
        ]
        if let v = cert.machineIdentifier { metadataDict["machineIdentifier"] = v }
        if let v = cert.machineName { metadataDict["machineName"] = v }
        if let v = cert.requesterEmail { metadataDict["requesterEmail"] = v }
        setCertificateMetadata(metadataDict, for: cert.serialNumber)
    }
    
    public func getLocalCertificate(serialNumber: String) -> ALTCertificate? {
        if let activeCert = self.activeCertificate, activeCert.serialNumber == serialNumber {
            debugLog("[CertificateManager] Found in active Keychain.shared.certificate")
            return activeCert.certificate
        }
        do {
            if let data = try self.keychain.getData(certKeyPrefix + serialNumber) {
                debugLog("[CertificateManager] Retrieved data size: \(data.count) for \(serialNumber)")
                var loadedCert: ALTCertificate?
                let savedPassword = getCertificateMetadata(for: serialNumber)?["machineIdentifier"]
                do {
                    loadedCert = try CertificateStore.load(data, password: savedPassword)
                    debugLog("[CertificateManager] Parsed as p12")
                } catch {
                    debugLog("[CertificateManager] Failed p12 parse: \(error)")
                    if let cert = ALTCertificate(data: data) {
                        loadedCert = cert
                        debugLog("[CertificateManager] Parsed as raw cert")
                    } else {
                        debugLog("[CertificateManager] Failed raw cert parsing")
                    }
                }
                if let cert = loadedCert {
                    if let metadata = getCertificateMetadata(for: serialNumber) {
                        cert.machineIdentifier = metadata["machineIdentifier"]
                        cert.machineName = metadata["machineName"]
                        cert.requesterEmail = metadata["requesterEmail"]
                    }
                    return cert
                }
            }
        } catch {
            debugLog("[CertificateManager] Error loading cert from keychain: \(error)")
        }
        return nil
    }
    
    public func getAllLocalCertificates() -> [ALTCertificate] {
        let serials = getImportedCertificateSerials()
        debugLog("[CertificateManager] getAllLocalCertificates count: \(serials.count)")
        var certs: [ALTCertificate] = []
        for serial in serials {
            if let cert = getLocalCertificate(serialNumber: serial) {
                certs.append(cert)
            }
        }
        return certs
    }
    
    public func deleteLocalCertificate(serialNumber: String) {
        debugLog("[CertificateManager] deleteLocalCertificate: \(serialNumber)")
        if self.activeCertificate?.serialNumber == serialNumber {
            try? clearActiveCertificate()
        }
        try? self.keychain.remove(certKeyPrefix + serialNumber)
        setCertificateMetadata(nil, for: serialNumber)
        var serials = getImportedCertificateSerials()
        serials.removeAll { $0 == serialNumber }
        setImportedCertificateSerials(serials)
    }
    
    public func isCertificateLocallyCached(serialNumber: String) -> Bool {
        if let activeCert = self.activeCertificate, activeCert.serialNumber == serialNumber {
            return true
        }
        return getImportedCertificateSerials().contains(serialNumber)
    }
    
    public func isCertificateLocallyCached(cert: ALTCertificate) -> Bool {
        if let activeCert = self.activeCertificate, activeCert.serialNumber == cert.serialNumber {
            return true
        }
        let serials = getImportedCertificateSerials()
        if serials.contains(cert.serialNumber) {
            return true
        }
        return false
    }
}

// MARK: - Private Domain Persistence Boundary Extension

private extension CertificateManager {
    func getImportedCertificateSerials() -> [String] {
        return UserDefaults.standard.stringArray(forKey: serialsKey) ?? []
    }
    
    func setImportedCertificateSerials(_ serials: [String]) {
        UserDefaults.standard.set(serials, forKey: serialsKey)
    }
    
    func getCertificateMetadata(for serial: String) -> [String: String]? {
        return UserDefaults.standard.dictionary(forKey: metadataPrefix + serial) as? [String: String]
    }
    
    func setCertificateMetadata(_ metadata: [String: String]?, for serial: String) {
        if let metadata = metadata {
            UserDefaults.standard.set(metadata, forKey: metadataPrefix + serial)
        } else {
            UserDefaults.standard.removeObject(forKey: metadataPrefix + serial)
        }
    }
}
