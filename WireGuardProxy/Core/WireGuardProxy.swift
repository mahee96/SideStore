//
//  WireGuardProxy.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation
import Network

class WireGuardProxy {
    private let config: ProxyConfiguration
    private let connection: UDPConnection
    private let handshake: HandshakeManager
    private let monitor: ConnectionMonitor
    private let statistics: TrafficStatistics
    private let encryption: EncryptionManager
    
    private var isRunning = false
    
    init(config: ProxyConfiguration) {
        self.config = config
        self.encryption = EncryptionManager(privateKey: config.serverPrivateKey, publicKey: config.clientPublicKey)
        self.connection = UDPConnection()
        self.handshake = HandshakeManager(timeout: config.handshakeTimeout, encryption: encryption)
        self.monitor = ConnectionMonitor(keepAliveInterval: config.keepAliveInterval)
        self.statistics = TrafficStatistics()
        
        setupHandlers()
    }
    
    func start() async throws {
        guard !isRunning else { return }
        
        // Start components
        try await connection.start(endpoint: createEndpoint())
        try await handshake.performHandshake()
        monitor.startMonitoring()
        
        isRunning = true
    }
    
    func stop() {
        isRunning = false
        // Stop all components
    }
    
    private func setupHandlers() {
        connection.onPacketReceived = { [weak self] data, context in
            self?.handlePacket(data, context: context)
        }
        
        monitor.onConnectionLost = { [weak self] in
            self?.handleConnectionLost()
        }
    }
    
    private func handlePacket(_ data: Data, context: NWConnection.Context) {
        Task {
            do {
                let packet = try WireGuardPacket.decrypt(data, using: encryption.currentKey)
                let processed = packet.swapAddresses()
                let encrypted = try processed.encrypt(using: encryption.currentKey)
                try await connection.send(encrypted)
                
                statistics.recordReceived(data.count)
                monitor.activityDetected()
            } catch {
                Logger.error("Packet processing failed: \(error)")
            }
        }
    }
}
