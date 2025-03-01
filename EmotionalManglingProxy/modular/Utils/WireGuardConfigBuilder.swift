//
//  WireGuardConfigBuilder.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import WireGuardKit
import Foundation

class WireGuardConfigBuilder {
    static func buildConfig(bindAddr: SocketAddress) throws -> TunnelConfiguration {
        // Read the keys from the bundle
        guard let serverPrivateKeyPath = Bundle.main.path(forResource: "server_privatekey", ofType: nil, inDirectory: "keys"),
              let clientPublicKeyPath = Bundle.main.path(forResource: "client_publickey", ofType: nil, inDirectory: "keys") else {
            throw ConfigError.missingKeyFiles
        }
        
        guard let serverPrivateKeyString = try? String(contentsOfFile: serverPrivateKeyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let clientPublicKeyString = try? String(contentsOfFile: clientPublicKeyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ConfigError.invalidKeyFiles
        }
        
        // Create WireGuard configuration
        guard let serverPrivateKey = PrivateKey(base64Key: serverPrivateKeyString),
              let clientPublicKey = PublicKey(base64Key: clientPublicKeyString) else {
            throw ConfigError.invalidKeys
        }
        
        // Create interface configuration
        var interface = InterfaceConfiguration(privateKey: serverPrivateKey)
        interface.addresses = [IPAddressRange(from: "10.7.0.1/24")!]
        interface.listenPort = UInt16(bindAddr.port)
        interface.dns = [DNSServer(from: "1.1.1.1")!]
        
        // Create peer configuration
        var peer = PeerConfiguration(publicKey: clientPublicKey)
        peer.allowedIPs = [IPAddressRange(from: "10.7.0.0/24")!]
        peer.endpoint = Endpoint(from: "127.0.0.1:51820")
        peer.persistentKeepAlive = 25
        
        // Create tunnel configuration
        return TunnelConfiguration(name: "EmotionalDamage", interface: interface, peers: [peer])
    }
    
    enum ConfigError: Error {
        case missingKeyFiles
        case invalidKeyFiles
        case invalidKeys
    }
}