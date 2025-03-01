//
//  NetworkSettingsBuilder.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import NetworkExtension
import WireGuardKit

struct NetworkSettingsBuilder {
    static func createSettings(from tunnelConfig: TunnelConfiguration) -> NEPacketTunnelNetworkSettings {
        // Get the first IP address from the interface
        let addressRange = tunnelConfig.interface.addresses.first!
        
        // Create network settings
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        // Configure IPv4 settings
        // Use the string representation of the IP address range
        let addressComponents = addressRange.stringRepresentation.split(separator: "/")
        let addressString = String(addressComponents[0])
        
        // Calculate subnet mask from CIDR prefix
        let prefixLength = Int(addressComponents[1]) ?? 24
        let subnetMaskString = subnetMaskFromPrefix(prefixLength)
        
        let ipv4Settings = NEIPv4Settings(addresses: [addressString], subnetMasks: [subnetMaskString])
        
        // Add all allowed IPs as routes
        var includedRoutes = [NEIPv4Route]()
        for peer in tunnelConfig.peers {
            for allowedIP in peer.allowedIPs {
                // Parse the IP address range
                let components = allowedIP.stringRepresentation.split(separator: "/")
                let ip = String(components[0])
                let prefix = Int(components[1]) ?? 32
                let mask = subnetMaskFromPrefix(prefix)
                
                // Only add IPv4 addresses (simple check)
                if ip.contains(".") {
                    includedRoutes.append(NEIPv4Route(destinationAddress: ip, subnetMask: mask))
                }
            }
        }
        
        ipv4Settings.includedRoutes = includedRoutes
        networkSettings.ipv4Settings = ipv4Settings
        
        // Configure DNS settings if specified
        if !tunnelConfig.interface.dns.isEmpty {
            let dnsServers = tunnelConfig.interface.dns.map { $0.stringRepresentation }
            let dnsSettings = NEDNSSettings(servers: dnsServers)
            
            if !tunnelConfig.interface.dnsSearch.isEmpty {
                dnsSettings.searchDomains = tunnelConfig.interface.dnsSearch
            }
            
            networkSettings.dnsSettings = dnsSettings
        }
        
        // Set MTU if specified
        if let mtu = tunnelConfig.interface.mtu {
            networkSettings.mtu = NSNumber(value: mtu)
        }
        
        return networkSettings
    }
    
    // Helper function to convert CIDR prefix to subnet mask
    private static func subnetMaskFromPrefix(_ prefix: Int) -> String {
        var mask = [UInt8](repeating: 0, count: 4)
        
        for i in 0..<4 {
            let bits = min(8, max(0, prefix - i * 8))
            mask[i] = UInt8(255 << (8 - bits))
        }
        
        return mask.map { String($0) }.joined(separator: ".")
    }
}
