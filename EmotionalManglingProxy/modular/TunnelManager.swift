//
//  TunnelManager.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import NetworkExtension
import Foundation
import os.log
import WireGuardKit

class TunnelManager {
    private let logger = LoggerService.shared.createLogger(category: "TunnelManager")
    private var observer: NSObjectProtocol?
    private var tunnel: NETunnelProviderManager?
    
    init() {}
    
    func startTunnel(with config: TunnelConfiguration, completion: @escaping (Error?) -> Void) {
        // Load any existing configurations
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Failed to load tunnel configurations: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            // Look for an existing configuration with the same name
            let manager = managers?.first(where: { $0.localizedDescription == "EmotionalDamage" }) ?? NETunnelProviderManager()
            
            // Configure the manager
            manager.localizedDescription = "EmotionalDamage"
            
            
            // Create protocol configuration
            let tunnelProviderProtocol = NETunnelProviderProtocol()
            tunnelProviderProtocol.providerBundleIdentifier = "com.sidestore.EmotionalDamage.NetworkExtension"
            tunnelProviderProtocol.serverAddress = "127.0.0.1"

            // Manually create the WgQuickConfig string
            var wgQuickConfig = "[Interface]\n"
            wgQuickConfig.append("PrivateKey = \(config.interface.privateKey.base64Key)\n")
            if let listenPort = config.interface.listenPort {
                wgQuickConfig.append("ListenPort = \(listenPort)\n")
            }
            // Add other interface properties...

            // Add peers
            for peer in config.peers {
                wgQuickConfig.append("\n[Peer]\n")
                wgQuickConfig.append("PublicKey = \(peer.publicKey.base64Key)\n")
                // Add other peer properties...
            }

//            tunnelProviderProtocol.providerConfiguration = ["WgQuickConfig": config.asWgQuickConfig()]
            tunnelProviderProtocol.providerConfiguration = ["WgQuickConfig": wgQuickConfig]
            manager.protocolConfiguration = tunnelProviderProtocol
            
            // Enable on demand
            manager.isEnabled = true
            
            // Save the configuration
            manager.saveToPreferences { [weak self] error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("Failed to save tunnel configuration: \(error.localizedDescription)")
                    completion(error)
                    return
                }
                
                // Start the tunnel
                do {
                    try manager.connection.startVPNTunnel()
                    self.tunnel = manager
                    
                    // Observe tunnel status changes
                    self.observer = NotificationCenter.default.addObserver(
                        forName: .NEVPNStatusDidChange,
                        object: manager.connection,
                        queue: .main
                    ) { [weak self] notification in
                        guard let self = self, let tunnel = self.tunnel else { return }
                        
                        let status = tunnel.connection.status
                        self.logger.info("Tunnel status changed: \(status.rawValue)")
                        
                        if status == .disconnected || status == .invalid {
                            // Try to reconnect if disconnected
                            do {
                                try tunnel.connection.startVPNTunnel()
                            } catch {
                                self.logger.error("Failed to restart tunnel: \(error.localizedDescription)")
                            }
                        }
                    }
                    
                    self.logger.info("EmotionalProxy started successfully")
                    completion(nil)
                } catch {
                    self.logger.error("Failed to start tunnel: \(error.localizedDescription)")
                    completion(error)
                }
            }
        }
    }
    
    func stopTunnel() {
        if let tunnel = tunnel {
            tunnel.connection.stopVPNTunnel()
            self.tunnel = nil
            
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            
            logger.info("EmotionalProxy stopped")
        }
    }
    
    var isActive: Bool {
        return tunnel != nil && tunnel!.connection.status == .connected
    }
    
    deinit {
        cleanup()
    }
    
    func cleanup() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        
        if let tunnel = tunnel {
            tunnel.connection.stopVPNTunnel()
            self.tunnel = nil
        }
    }
}
