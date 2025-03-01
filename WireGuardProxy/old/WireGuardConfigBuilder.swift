//
//  WireGuardConfigBuilder.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation
import Foundation

enum ConfigError: Error {
    case missingKeyFiles
    case invalidKeyFormat
    case fileReadError
}

class WireGuardConfigBuilder {
    static func readServerPrivateKey() throws -> [UInt8] {
        return try decodeBase64Key(readServerPrivateKey())
    }
    
    static func readServerPrivateKey() throws -> String {
        guard let keyPath = BundleToken.bundle.path(forResource: "server_privatekey", ofType: nil),
              let keyData = try? String(contentsOfFile: keyPath, encoding: .utf8) else
        {
            throw ConfigError.missingKeyFiles
        }
        
        let keyString = String(keyData.prefix(44))
        return keyString
    }
    
    private static func decodeBase64Key(_ keyString: String) throws -> [UInt8] {
        guard let data = Data(base64Encoded: keyString) else
        {
            throw ConfigError.invalidKeyFormat
        }
        return [UInt8](data)
    }
    
    static func readClientPublicKey() throws -> [UInt8] {
        return try decodeBase64Key(readClientPublicKey())
    }
    
    static func readClientPublicKey() throws -> String {
        guard let keyPath = BundleToken.bundle.path(forResource: "client_publickey", ofType: nil),
              let keyData = try? String(contentsOfFile: keyPath, encoding: .utf8) else
        {
            throw ConfigError.missingKeyFiles
        }
        
        let keyString = String(keyData.prefix(44))
        return keyString
    }
    
    // Helper for bundle access
    private class BundleToken {
        static let bundle: Bundle = {
            let bundleForClass = Bundle(for: BundleToken.self)
            return bundleForClass
        }()
    }
}
