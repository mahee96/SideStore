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
import Security

public struct ActiveSigningCertificate: Sendable {
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
    
    private let serialsKey = "importedCertificateSerials"
    private let metadataPrefix = "certMetadata_"
    
    public private(set) var activeCertificate: ActiveSigningCertificate?
    
    private init() {
        _ = try? loadActiveCertificate()
    }
    
    // MARK: - Active Keychain Certificate Encapsulation
    
    /// Loads active signing certificate from Keychain into memory.
    @discardableResult
    public func loadActiveCertificate() throws -> ActiveSigningCertificate? {
        guard let data = Keychain.shared.signingCertificate else {
            debugLog("[CertificateManager] loadActiveCertificate: No signingCertificate data found in Keychain.")
            self.activeCertificate = nil
            return nil
        }
        let password = Keychain.shared.signingCertificatePassword
        do {
            let cert = try CertificateStore.load(data, password: password)
            let active = ActiveSigningCertificate(certificate: cert, p12Data: data, password: password)
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
            guard cert.privateKey != nil else {
                debugLog("[CertificateManager] setActiveCertificate failed: Certificate \(cert.serialNumber) lacks a private key.")
                throw ALTCertificateError.invalidFormat(cause: "Target Certificate lacks a private key. Cannot be used as active signing certificate")
            }
            do {
                let p12Data = try CertificateStore.export(cert, password: cert.machineIdentifier)
                Keychain.shared.signingCertificate = p12Data
                Keychain.shared.signingCertificatePassword = cert.machineIdentifier
                saveCertificate(cert)
                let active = ActiveSigningCertificate(certificate: cert, p12Data: p12Data, password: cert.machineIdentifier)
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
    public func clearActiveCertificate() {
        debugLog("[CertificateManager] clearActiveCertificate: Clearing active certificate.")
        self.activeCertificate = nil
        Keychain.shared.signingCertificate = nil
        Keychain.shared.signingCertificatePassword = nil
    }
    
    // MARK: - Certificate Encoding Helpers
    
    public var activeSigningCertificateBase64Encoded: String? {
        guard let data = activeCertificate?.p12Data else { return nil }
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
                Keychain.shared[certificateSerial: cert.serialNumber] = p12Data
                debugLog("[CertificateManager] Successfully saved p12 to keychain")
            } catch {
                debugLog("[CertificateManager] Failed to export/save p12 to keychain: \(error)")
            }
        } else if let derData = cert.data {
            debugLog("[CertificateManager] derData exists, size: \(derData.count)")
            Keychain.shared[certificateSerial: cert.serialNumber] = derData
            debugLog("[CertificateManager] Successfully saved der to keychain")
        }
        
        let serials = getImportedCertificateSerials()
        if !serials.contains(cert.serialNumber) {
            var updatedSerials = serials
            updatedSerials.append(cert.serialNumber)
            setImportedCertificateSerials(updatedSerials)
        }
        
        var metadataDict: [String: String] = getCertificateMetadata(for: cert.serialNumber) ?? [:]
        metadataDict["name"] = cert.name
        metadataDict["serialNumber"] = cert.serialNumber
        metadataDict["hasPrivateKey"] = cert.privateKey != nil ? "true" : "false"
        if let v = cert.machineIdentifier { metadataDict["machineIdentifier"] = v }
        if let v = cert.machineName { metadataDict["machineName"] = v }
        if let v = cert.requesterEmail { metadataDict["requesterEmail"] = v }
        setCertificateMetadata(metadataDict, for: cert.serialNumber)
    }
    
    public func getLocalCertificate(serialNumber: String) -> ALTCertificate? {
        if let active = self.activeCertificate, active.serialNumber == serialNumber {
            return active.certificate
        }
        if let data = Keychain.shared[certificateSerial: serialNumber] {
            if data.isPKCS12 {
                let savedPassword = getCertificateMetadata(for: serialNumber)?["machineIdentifier"]
                if let cert = try? CertificateStore.load(data, password: savedPassword) {
                    if let metadata = getCertificateMetadata(for: serialNumber) {
                        cert.machineIdentifier = metadata["machineIdentifier"]
                        cert.machineName = metadata["machineName"]
                        cert.requesterEmail = metadata["requesterEmail"]
                    }
                    return cert
                }
            } else {
                if let cert = ALTCertificate(data: data) {
                    if let metadata = getCertificateMetadata(for: serialNumber) {
                        cert.machineIdentifier = metadata["machineIdentifier"]
                        cert.machineName = metadata["machineName"]
                        cert.requesterEmail = metadata["requesterEmail"]
                    }
                    return cert
                }
            }
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
            clearActiveCertificate()
        }
        Keychain.shared[certificateSerial: serialNumber] = nil
        setCertificateMetadata(nil, for: serialNumber)
        var serials = getImportedCertificateSerials()
        serials.removeAll { $0 == serialNumber }
        setImportedCertificateSerials(serials)
    }
    
    // MARK: - Compatibility Helper Aliases
    
    public func loadCertificate(for serialNumber: String) -> ALTCertificate? {
        return getLocalCertificate(serialNumber: serialNumber)
    }

    public func loadCertificate(fromProvisioningProfileAt url: URL) -> ALTCertificate? {
        // Try to get the exact signing certificate from the bundle binary first
        let appURL = url.deletingLastPathComponent()
        if appURL.pathExtension == "app", let binaryCert = getSigningCertificate(at: appURL) {
            return binaryCert
        }
        
        guard let profile = ALTProvisioningProfile(url: url), let cert = profile.certificates.first else {
            return nil
        }
        if let localCopy = getLocalCertificate(serialNumber: cert.serialNumber) {
            if cert.machineName == nil { cert.machineName = localCopy.machineName }
            if cert.machineIdentifier == nil { cert.machineIdentifier = localCopy.machineIdentifier }
            if cert.requesterEmail == nil { cert.requesterEmail = localCopy.requesterEmail }
        }
        return cert
    }

    public func loadAllLocalCertificates() -> [ALTCertificate] {
        return getAllLocalCertificates()
    }

    public func getSignableCertificate(for serialNumber: String) -> ALTCertificate? {
        guard let cert = getLocalCertificate(serialNumber: serialNumber) else { return nil }
        guard cert.privateKey != nil else {
            debugLog("[CertificateManager] getSignableCertificate: Certificate \(serialNumber) found in cache, but lacks local private key (only public key/DER is available).")
            return nil
        }
        return cert
    }

    public func getSigningCertificate(at url: URL, withPlistFallback: Bool = true) -> ALTCertificate? {
        let appDirectory = url.pathExtension == "app" ? url.deletingLastPathComponent() : url
        let certURL = appDirectory.appendingPathComponent("signing_certificate.der")
        
        // 1. Try to load cached signing_certificate.der file (new way uses cachedCert)
        if FileManager.default.fileExists(atPath: certURL.path) {
            if let derData = try? Data(contentsOf: certURL), let cert = ALTCertificate(data: derData) {
                debugLog("[CertificateManager] getSigningCertificate: Loaded cached signing certificate from \(certURL.path)")
                return cert
            }
        }
        
        // 2. Fall back to active signing certificate for legacy users
        debugLog("[CertificateManager] getSigningCertificate: Cached certificate not found. Falling back to active certificate.")
        return activeCertificate?.certificate
    }

    public func loadAllSignableLocalCertificates() -> [ALTCertificate] {
        return getAllLocalCertificates().filter { $0.privateKey != nil }
    }

    public func deleteCertificate(serialNumber: String) {
        deleteLocalCertificate(serialNumber: serialNumber)
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
