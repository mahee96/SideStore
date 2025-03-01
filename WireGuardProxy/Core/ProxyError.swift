//
//  ProxyError.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation

enum ProxyError: Error {
    case socketBindFailed
    case encryptionFailed
    case invalidEndpoint
    case handshakeFailed
    case invalidConfiguration
    case connectionTimeout
    case packetProcessingFailed
    
    var localizedDescription: String {
        switch self {
        case .socketBindFailed: return "Failed to bind UDP socket"
        case .encryptionFailed: return "Encryption operation failed"
        case .invalidEndpoint: return "Invalid endpoint configuration"
        case .handshakeFailed: return "WireGuard handshake failed"
        case .invalidConfiguration: return "Invalid proxy configuration"
        case .connectionTimeout: return "Connection timed out"
        case .packetProcessingFailed: return "Failed to process packet"
        }
    }
}