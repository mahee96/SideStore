//
//  ProxyConfiguration.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation

public struct ProxyConfiguration {
    let serverPrivateKey: String
    let clientPublicKey: String
    let bindAddress: String
    let bindPort: UInt16
    
    // Optional configurations with defaults
    let mtu: UInt16
    let keepAliveInterval: TimeInterval
    let handshakeTimeout: TimeInterval
    
    static let defaultConfiguration = ProxyConfiguration(
        serverPrivateKey: "",
        clientPublicKey: "",
        bindAddress: "127.0.0.1",
        bindPort: 51820,
        mtu: 1420,
        keepAliveInterval: 15,
        handshakeTimeout: 5
    )
}
