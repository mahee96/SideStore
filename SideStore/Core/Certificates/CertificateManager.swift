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

public final class CertificateManager: @unchecked Sendable {
    public static let shared = CertificateManager()
    
    private let keychain = KeychainAccess.Keychain(service: Bundle.Info.appbundleIdentifier)
        .accessibility(.afterFirstUnlock)
        .synchronizable(true)
        
    private let serialsKey = "importedCertificateSerials"
    private let metadataPrefix = "certMetadata_"
    private let certKeyPrefix = "importedCert_"
    
    private init() {}
    
    // MARK: - Active Keychain Certificate Encapsulation
    
    public var activeCertificate: ALTCertificate? {
        get { Keychain.shared.certificate }
        set {
            Keychain.shared.certificate = newValue
            if let cert = newValue {
                Keychain.shared.signingCertificate = cert.p12Data()
                Keychain.shared.signingCertificatePassword = cert.machineIdentifier ?? ""
                saveCertificate(cert)
            } else {
                Keychain.shared.signingCertificate = nil
                Keychain.shared.signingCertificatePassword = nil
            }
        }
    }
    
    public var activeSigningCertificateData: Data? {
        return Keychain.shared.signingCertificate
    }
    
    public var activeSigningCertificatePassword: String? {
        return Keychain.shared.signingCertificatePassword
    }
    
    public func clearActiveCertificate() {
        self.activeCertificate = nil
    }
    
    public func saveCertificate(_ cert: ALTCertificate) {
        debugLog("[CertificateManager] saveCertificate started for serial: \(cert.serialNumber)")
        defer { debugLog("[CertificateManager] saveCertificate completed for serial: \(cert.serialNumber)") }
        
        if cert.privateKey != nil, let p12Data = cert.p12Data() {
            debugLog("[CertificateManager]   p12Data generated, size: \(p12Data.count)")
            do {
                try self.keychain.set(p12Data, key: certKeyPrefix + cert.serialNumber)
                debugLog("[CertificateManager]   Successfully saved p12 to keychain")
            } catch {
                debugLog("[CertificateManager]   Failed to save p12 to keychain: \(error)")
            }
        } else if let derData = cert.data {
            debugLog("[CertificateManager]   derData exists, size: \(derData.count)")
            do {
                try self.keychain.set(derData, key: certKeyPrefix + cert.serialNumber)
                debugLog("[CertificateManager]   Successfully saved derData to keychain")
            } catch {
                debugLog("[CertificateManager]   Failed to save derData to keychain: \(error)")
            }
        } else {
            debugLog("[CertificateManager]   No data available to save")
            return
        }
        
        var serials = getImportedCertificateSerials()
        if !serials.contains(cert.serialNumber) {
            serials.append(cert.serialNumber)
            setImportedCertificateSerials(serials)
        }
        
        var metadataDict: [String: String] = [:]
        if let v = cert.machineName       { metadataDict["machineName"]       = v }
        if let v = cert.identifier        { metadataDict["identifier"]        = v }
        if let v = cert.requesterEmail    { metadataDict["requesterEmail"]    = v }
        if let v = cert.machineIdentifier { metadataDict["machineIdentifier"] = v }
        setCertificateMetadata(metadataDict, for: cert.serialNumber)
    }
    
    public func deleteCertificate(serialNumber: String) {
        debugLog("[CertificateManager] deleteCertificate started for serial: \(serialNumber)")
        defer { debugLog("[CertificateManager] deleteCertificate completed for serial: \(serialNumber)") }
        
        try? self.keychain.remove(certKeyPrefix + serialNumber)
        
        var serials = getImportedCertificateSerials()
        serials.removeAll { $0 == serialNumber }
        setImportedCertificateSerials(serials)
        
        setCertificateMetadata(nil, for: serialNumber)
    }
    
    public func loadCertificate(for serialNumber: String) -> ALTCertificate? {
        debugLog("[CertificateManager] loadCertificate started for serial: \(serialNumber)")
        defer { debugLog("[CertificateManager] loadCertificate completed for serial: \(serialNumber)") }
        
        if let activeCert = Keychain.shared.certificate, activeCert.serialNumber == serialNumber {
            debugLog("[CertificateManager]   Found in active Keychain.shared.certificate")
            return activeCert
        }
        do {
            if let data = try self.keychain.getData(certKeyPrefix + serialNumber) {
                debugLog("[CertificateManager]   Retrieved data size: \(data.count) for \(serialNumber)")
                var loadedCert: ALTCertificate?
                do {
                    loadedCert = try ALTCertificate(p12Data: data, password: "")
                    debugLog("[CertificateManager]   Parsed as p12 empty pass")
                } catch {
                    debugLog("[CertificateManager]   Failed p12 empty pass: \(error)")
                    do {
                        loadedCert = try ALTCertificate(p12Data: data, password: nil)
                        debugLog("[CertificateManager]   Parsed as p12 nil pass")
                    } catch {
                        debugLog("[CertificateManager]   Failed p12 nil pass: \(error)")
                        if let cert = ALTCertificate(data: data) {
                            loadedCert = cert
                            debugLog("[CertificateManager]   Parsed as raw cert")
                        } else {
                            debugLog("[CertificateManager]   Failed raw cert parsing")
                        }
                    }
                }
                
                if let cert = loadedCert {
                    if let metadata = getCertificateMetadata(for: cert.serialNumber) {
                        cert.machineName       = metadata["machineName"]
                        cert.identifier        = metadata["identifier"]
                        cert.requesterEmail    = metadata["requesterEmail"]
                        cert.machineIdentifier = metadata["machineIdentifier"]
                    }
                    return cert
                }
            } else {
                debugLog("[CertificateManager]   No data found in keychain for \(certKeyPrefix)\(serialNumber)")
            }
        } catch {
            debugLog("[CertificateManager]   Keychain error for \(certKeyPrefix)\(serialNumber): \(error)")
        }
        return nil
    }
    
    public func loadAllLocalCertificates() -> [ALTCertificate] {
        debugLog("[CertificateManager] loadAllLocalCertificates started")
        defer { debugLog("[CertificateManager] loadAllLocalCertificates completed") }
        
        let serials = getImportedCertificateSerials()
        debugLog("[CertificateManager]   Registered local serials: \(serials)")
        var results: [ALTCertificate] = []
        for serial in serials {
            if let cert = loadCertificate(for: serial) {
                results.append(cert)
            }
        }
        return results
    }
    
    public func loadAllSignableLocalCertificates() -> [ALTCertificate] {
        debugLog("[CertificateManager] loadAllSignableLocalCertificates started")
        defer { debugLog("[CertificateManager] loadAllSignableLocalCertificates completed") }
        
        let allCerts = self.loadAllLocalCertificates()
        let signable = allCerts.filter { $0.privateKey != nil }
        debugLog("[CertificateManager]   Total signable certificates found: \(signable.count) of \(allCerts.count)")
        return signable
    }
    
    public func isCertificateLocallyCached(serialNumber: String) -> Bool {
        if let activeCert = self.activeCertificate, activeCert.serialNumber == serialNumber {
            return true
        }
        return getImportedCertificateSerials().contains(serialNumber)
    }
    
    public func isCertificateLocallyCached(cert: ALTCertificate) -> Bool {
        if let activeCert = self.activeCertificate, activeCert.serialNumber == cert.serialNumber {
            if cert.privateKey == nil || activeCert.privateKey != nil {
                return true
            }
        }
        if let existing = loadCertificate(for: cert.serialNumber) {
            if cert.privateKey == nil || existing.privateKey != nil {
                return true
            }
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
