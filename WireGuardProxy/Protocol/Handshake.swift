//
//  HandshakeManager.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation
import CryptoKit

class HandshakeManager {
    private var lastHandshakeTime: Date?
    private let timeout: TimeInterval
    private let encryption: EncryptionManager
    private let connection: UDPConnection
    
    enum HandshakeError: Error {
        case initiationFailed
        case responseTimeout
        case invalidResponse
        case sessionCreationFailed
    }
    
    init(timeout: TimeInterval, encryption: EncryptionManager, connection: UDPConnection) {
        self.timeout = timeout
        self.encryption = encryption
        self.connection = connection
    }
    
    func performHandshake() async throws {
        Logger.info("Starting handshake")
        let handshakePacket = try await createHandshakeInitiation()
        try await sendHandshakePacket(handshakePacket)
        try await waitForHandshakeResponse()
        lastHandshakeTime = Date()
        Logger.info("Handshake completed successfully")
    }
    
    private func createHandshakeInitiation() async throws -> Data {
        // Create handshake initiation packet
        var packet = Data()
        
        // 1. Message type (1 byte for handshake initiation)
        packet.append(1) // Type 1 = Handshake initiation
        
        // 2. Generate ephemeral key pair
        let ephemeralPrivateKey = try encryption.generateEphemeralKey()
        let ephemeralPublicKey = try encryption.derivePublicKey(from: ephemeralPrivateKey)
        packet.append(ephemeralPublicKey)
        
        // 3. Add timestamp for replay protection
        let timestamp = UInt64(Date().timeIntervalSince1970)
        packet.append(timestamp.bigEndianBytes)
        
        // 4. Generate MAC for packet authentication
        let mac = try encryption.generateMAC(for: packet)
        packet.append(mac)
        
        return packet
    }
    
    private func sendHandshakePacket(_ packet: Data) async throws {
        try await connection.send(packet)
    }
    
    private func waitForHandshakeResponse() async throws {
        // Set up timeout
        let timeoutDate = Date().addingTimeInterval(timeout)
        
        while Date() < timeoutDate {
            if let response = try await connection.receiveWithTimeout(timeout) {
                if try validateHandshakeResponse(response) {
                    // Generate session key from handshake
                    try encryption.generateSessionKey()
                    return
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        throw HandshakeError.responseTimeout
    }
    
    private func validateHandshakeResponse(_ response: Data) throws -> Bool {
        guard response.count >= 4 else {
            throw HandshakeError.invalidResponse
        }
        
        // 1. Check message type (should be 2 for handshake response)
        guard response[0] == 2 else {
            return false
        }
        
        // 2. Verify MAC
        let messageData = response.dropLast(16) // Last 16 bytes are MAC
        let receivedMAC = response.suffix(16)
        let calculatedMAC = try encryption.generateMAC(for: messageData)
        
        guard receivedMAC == calculatedMAC else {
            return false
        }
        
        return true
    }
    
    func needsHandshake() -> Bool {
        guard let lastHandshake = lastHandshakeTime else { return true }
        return Date().timeIntervalSince(lastHandshake) > timeout
    }
}

// Helper extension for converting numbers to bytes
extension UInt64 {
    var bigEndianBytes: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }
}
