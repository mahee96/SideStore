//
//  class.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import Foundation
import WireGuardKit
import WireGuardKitGo

class WireGuardTunnel {
    enum TunnelError: Error {
        case invalidKey
        case initializationFailed
    }
    
    private let serverPrivateKey: PrivateKey
    private let clientPublicKey: PublicKey
    private var handle: Int32 = -1
    
    init(serverPrivateKey: [UInt8], clientPublicKey: [UInt8]) throws {
        guard let privateKey = PrivateKey(rawValue: Data(serverPrivateKey)),
              let publicKey = PublicKey(rawValue: Data(clientPublicKey)) else {
            throw TunnelError.invalidKey
        }
        
        self.serverPrivateKey = privateKey
        self.clientPublicKey = publicKey
        
        // Create WireGuard config string directly
        let config = """
        private_key=\(privateKey.base64Key)
        public_key=\(publicKey.base64Key)
        allowed_ip=10.7.0.0/24
        """
        
        handle = wgTurnOn(config.cString(using: .utf8), -1)
        if handle < 0 {
            throw TunnelError.initializationFailed
        }
    }
    
    deinit {
        if handle >= 0 {
            wgTurnOff(handle)
        }
    }
}
