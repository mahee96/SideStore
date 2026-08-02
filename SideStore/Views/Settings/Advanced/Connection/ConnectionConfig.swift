//
//  ConnectionConfig.swift
//  AltStore
//
//  Created by Magesh K on 02/03/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

final class ConnectionConfig: ObservableObject {
    static let shared = ConnectionConfig()

    private static var defaultOverrideIP: String { AppConstants.Connection.defaultOverrideIP }
    private static var defaultRemoteServerIP: String { AppConstants.Connection.defaultRemoteServerIP }

    @Published var tunnelIfaceIp: String?
    @Published var tunnelIfaceSubnetMask: String?
    @Published var tunnelPeerIp: String?
    @Published var overrideTunnelPeerIp: String = overrideIPStorage {
        didSet { Self.overrideIPStorage = overrideTunnelPeerIp }
    }
    @Published var overrideTunnelPeerReachable: Bool = false

    @Published var remoteServerIp: String = remoteServerIPStorage {
        didSet { Self.remoteServerIPStorage = remoteServerIp }
    }
    @Published var remotePeerIp: String?
    @Published var remoteReachable: Bool = false

    @Published var useLocalVPN: Bool = useLocalVPNStorage {
        didSet { Self.useLocalVPNStorage = useLocalVPN }
    }

    private static var overrideIPStorage: String {
        get { getStoredOverrideIP(default: defaultOverrideIP) }
        set { setStoredOverrideIP(newValue) }
    }

    private static var remoteServerIPStorage: String {
        get { getStoredRemoteServerIP(default: defaultRemoteServerIP) }
        set { setStoredRemoteServerIP(newValue) }
    }

    private static var useLocalVPNStorage: Bool {
        get { UserDefaults.standard.useLocalVPN }
        set { UserDefaults.standard.useLocalVPN = newValue }
    }

    var overrideTunnelPeerActive: ActiveState { overrideTunnelPeerReachable ? .yes : .no }
    var remoteActive: ActiveState { remoteReachable ? .yes : .no }
}

// MARK: - Private ConnectionConfig Domain Persistence Extension

private extension ConnectionConfig {
    static func getStoredOverrideIP(default defaultIP: String) -> String {
        return UserDefaults.standard.string(forKey: "TunnelOverridePeerIp") ?? defaultIP
    }
    
    static func setStoredOverrideIP(_ ip: String) {
        UserDefaults.standard.set(ip, forKey: "TunnelOverridePeerIp")
    }
    
    static func getStoredRemoteServerIP(default defaultIP: String) -> String {
        return UserDefaults.standard.string(forKey: "RemoteServerIp") ?? defaultIP
    }
    
    static func setStoredRemoteServerIP(_ ip: String) {
        UserDefaults.standard.set(ip, forKey: "RemoteServerIp")
    }
}
