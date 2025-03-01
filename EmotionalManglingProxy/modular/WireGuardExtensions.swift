//
//  TunnelConfigurationExtensions.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation
import WireGuardKit

extension TunnelConfiguration {
    
    public func asWgQuickConfig() -> String {
        var output = "[Interface]\n"
        output.append("PrivateKey = \(interface.privateKey.base64Key)\n")
        if let listenPort = interface.listenPort {
            output.append("ListenPort = \(listenPort)\n")
        }
        if !interface.addresses.isEmpty {
            let addressString = interface.addresses.map { $0.stringRepresentation }.joined(separator: ", ")
            output.append("Address = \(addressString)\n")
        }
        if !interface.dns.isEmpty {
            let dnsString = interface.dns.map { $0.stringRepresentation }.joined(separator: ", ")
            output.append("DNS = \(dnsString)\n")
        }
        if !interface.dnsSearch.isEmpty {
            let dnsSearchString = interface.dnsSearch.joined(separator: ", ")
            output.append("DNSSearch = \(dnsSearchString)\n")
        }
        if let mtu = interface.mtu {
            output.append("MTU = \(mtu)\n")
        }

        for peer in peers {
            output.append("\n[Peer]\n")
            output.append("PublicKey = \(peer.publicKey.base64Key)\n")
            if let preSharedKey = peer.preSharedKey?.base64Key {
                output.append("PresharedKey = \(preSharedKey)\n")
            }
            if !peer.allowedIPs.isEmpty {
                let allowedIPsString = peer.allowedIPs.map { $0.stringRepresentation }.joined(separator: ", ")
                output.append("AllowedIPs = \(allowedIPsString)\n")
            }
            if let endpoint = peer.endpoint {
                output.append("Endpoint = \(endpoint.stringRepresentation)\n")
            }
            if let persistentKeepAlive = peer.persistentKeepAlive {
                output.append("PersistentKeepalive = \(persistentKeepAlive)\n")
            }
        }

        return output
    }
}
