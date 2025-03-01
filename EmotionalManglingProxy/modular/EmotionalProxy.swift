//
//  EmotionalProxy.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation
import os.log

class EmotionalProxy {
    private let logger = LoggerService.shared.createLogger(category: "EmotionalProxy")
    private let tunnelManager = TunnelManager()
    private var workItem: DispatchWorkItem?
    
    static let shared = EmotionalProxy()
    
    private init() {}
    
    func start(bindAddr: SocketAddress) -> DispatchWorkItem {
        // Create a cancellable work item
        let workItem = DispatchWorkItem { [weak self] in
            self?.stop()
            self?.logger.info("EMP instructed to die")
        }
        
        self.workItem = workItem
        
        do {
            // Build WireGuard configuration
            let config = try WireGuardConfigBuilder.buildConfig(bindAddr: bindAddr)
            
            // Start the tunnel
            tunnelManager.startTunnel(with: config) { [weak self] error in
                if let error = error {
                    self?.logger.error("Failed to start tunnel: \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Failed to build WireGuard configuration: \(error.localizedDescription)")
        }
        
        return workItem
    }
    
    func stop() {
        tunnelManager.stopTunnel()
        workItem = nil
    }
    
    func test(timeout: Int32) -> Bool {
        // First check if the tunnel is active
        if !tunnelManager.isActive {
            return false
        }
        
        // Then perform a UDP test
        return UDPTester.testConnection(timeoutMs: Int(timeout))
    }
}