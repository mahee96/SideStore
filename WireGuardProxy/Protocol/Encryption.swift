//
//  Encryption.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation
import CryptoKit

class EncryptionManager {
    private let privateKey: Data
    private let publicKey: Data
    private var sessionKey: Data?
    private let queue = DispatchQueue(label: "com.wireguard.encryption")
    
    enum EncryptionError: Error {
        case invalidKeyFormat
        case keyGenerationFailed
        case encryptionFailed
        case decryptionFailed
        case noSessionKey
    }
    
    init(privateKey: String, publicKey: String) throws {
        guard let privKey = Data(base64Encoded: privateKey),
              let pubKey = Data(base64Encoded: publicKey) else {
            throw EncryptionError.invalidKeyFormat
        }
        
        self.privateKey = privKey
        self.publicKey = pubKey
    }
    
    var currentKey: Data {
        queue.sync {
            sessionKey ?? privateKey
        }
    }
    
    func generateSessionKey() throws -> Data {
        queue.sync {
            // This is a simplified version. In reality, you'd:
            // 1. Generate an ephemeral key pair
            // 2. Perform Diffie-Hellman key exchange
            // 3. Apply HKDF to derive the session key
            let newKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            sessionKey = newKey
            return newKey
        }
    }
    
    func encrypt(_ data: Data) throws -> Data {
        guard let key = queue.sync(execute: { sessionKey }) else {
            throw EncryptionError.noSessionKey
        }
        
        // This is a simplified version. In reality, you'd:
        // 1. Generate a nonce
        // 2. Use ChaCha20-Poly1305 for encryption
        // 3. Include necessary WireGuard headers
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try ChaChaPoly.seal(data, using: symmetricKey)
        return sealedBox.combined
    }
    
    func decrypt(_ data: Data) throws -> Data {
        guard let key = queue.sync(execute: { sessionKey }) else {
            throw EncryptionError.noSessionKey
        }
        
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try ChaChaPoly.SealedBox(combined: data)
        return try ChaChaPoly.open(sealedBox, using: symmetricKey)
    }
}

// Add these methods to the existing EncryptionManager class

extension EncryptionManager {
    func generateEphemeralKey() throws -> Data {
        // Generate random 32-byte private key
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw EncryptionError.keyGenerationFailed
        }
        return Data(bytes)
    }
    
    func derivePublicKey(from privateKey: Data) throws -> Data {
        // In a real implementation, this would use X25519
        // This is a simplified version
        let hash = SHA256.hash(data: privateKey)
        return Data(hash)
    }
    
    func generateMAC(for data: Data) throws -> Data {
        // In a real implementation, this would use Poly1305
        // This is a simplified version using HMAC-SHA256
        let key = SymmetricKey(data: currentKey)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(mac)
    }
}
