//
//  PacketTunnelProvider.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import NetworkExtension
import WireGuardKit
import os.log


class PacketTunnelProvider: NEPacketTunnelProvider {
    private var wireguardAdapter: WireGuardAdapter?
    private let logger = LoggerService.shared.createLogger(category: "PacketTunnelProvider")
    
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting Emotional Damage tunnel")
        
        // Instead of parsing the WgQuickConfig from the provider configuration,
        // use your WireGuardConfigBuilder directly
        let tunnelConfig: TunnelConfiguration
        do {
            // Create a socket address for binding
            let bindAddr = SocketAddress(host: "127.0.0.1", port: 51820) // Use appropriate values
            tunnelConfig = try WireGuardConfigBuilder.buildConfig(bindAddr: bindAddr)
        } catch {
            logger.error("Failed to build WireGuard configuration: \(error.localizedDescription)")
            completionHandler(error)
            return
        }
        
        // Setup tunnel settings
        let networkSettings = NetworkSettingsBuilder.createSettings(from: tunnelConfig)
        
        // Apply network settings
        setTunnelNetworkSettings(networkSettings) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Failed to set tunnel network settings: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            
            // Create the WireGuard adapter with the correct initializer
            self.wireguardAdapter = WireGuardAdapter(with: self) { logLevel, message in
                switch logLevel {
                case .verbose:
                    self.logger.debug("\(message)")
                case .error:
                    self.logger.error("\(message)")
                default:
                    self.logger.info("\(message)")
                }
            }
            
            // Start the adapter with the tunnel configuration
            self.wireguardAdapter?.start(tunnelConfiguration: tunnelConfig) { error in
                if let error = error {
                    self.logger.error("Failed to start WireGuard adapter: \(error.localizedDescription)")
                    completionHandler(error)
                    return
                }
                
                self.logger.info("Emotional Damage tunnel started successfully")
                completionHandler(nil)
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping Emotional Damage tunnel with reason: \(reason.rawValue)")
        
        wireguardAdapter?.stop { [weak self] error in
            if let error = error {
                self?.logger.error("Error stopping WireGuard adapter: \(error.localizedDescription)")
            }
            
            self?.logger.info("Emotional Damage tunnel stopped")
            completionHandler()
        }
    }
}
