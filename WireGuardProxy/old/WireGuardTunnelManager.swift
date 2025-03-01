//
//  WireGuardTunnelManager.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import Foundation
import WireGuardKitGo  // This module provides the wg* functions

enum TunnelError: Error {
    case invalidKey
    case initializationFailed
    case missingTunFd
}


/// A pure userspace WireGuard tunnel manager using low‑level WireGuardKitGo bindings.
/// This does NOT rely on Apple's NetworkExtension framework.
class WireGuardTunnelManager {
    // Remove WGInterface and instead use an Int32 handle returned by wgTurnOn.
    private var backendHandle: Int32 = -1

    // Store keys as Strings (assumed to be in Base64 format)
    private let serverPrivateKey: String
    private let clientPublicKey: String
    
    // The TUN file descriptor (must be opened elsewhere in your code)
    private let tunFd: Int32

    /// Initialize with keys and a TUN file descriptor.
    init(serverPrivateKey: String, clientPublicKey: String, tunFd: Int32) throws {
        guard tunFd >= 0 else {
            throw TunnelError.missingTunFd
        }
        self.serverPrivateKey = serverPrivateKey
        self.clientPublicKey = clientPublicKey
        self.tunFd = tunFd
    }
    
    /// Builds a UAPI configuration string for WireGuard.
    /// (This format must match what your WireGuard backend expects.)
    func buildUAPIConfiguration() -> String {
        // For demonstration, a simple line-based configuration:
        """
        private_key=\(serverPrivateKey)
        listen_port=51820
        public_key=\(clientPublicKey)
        allowed_ips=0.0.0.0/0
        endpoint=1.2.3.4:51820
        """
    }
    
    /// Starts the WireGuard tunnel.
    func startTunnel(completion: @escaping (Error?) -> Void) {
        let configStr = buildUAPIConfiguration()
        configStr.withCString { cStr in
            let handle = wgTurnOn(cStr, tunFd)
            if handle < 0 {
                completion(TunnelError.initializationFailed)
            } else {
                self.backendHandle = handle
                print("Tunnel started with handle: \(handle)")
                completion(nil)
            }
        }
    }
    
    /// Stops the WireGuard tunnel.
    func stopTunnel(completion: @escaping (Error?) -> Void) {
        wgTurnOff(backendHandle)
        print("Tunnel stopped.")
        completion(nil)
    }
    
    /// Sets a new configuration.
    func setConfig(_ newConfig: String) -> Int64 {
        return newConfig.withCString { cStr in
            return wgSetConfig(backendHandle, cStr)
        }
    }
    
    /// Retrieves the current configuration as a string.
    func getConfig() -> String? {
        guard let cStr = wgGetConfig(backendHandle) else { return nil }
        let config = String(cString: cStr)
        free(cStr)
        return config
    }
    
    /// Bump sockets, if needed.
    func bumpSockets() {
        wgBumpSockets(backendHandle)
    }
    
    /// Disable roaming semantics.
    func disableRoaming() {
        wgDisableSomeRoamingForBrokenMobileSemantics(backendHandle)
    }
    
    /// Returns the WireGuard backend version.
    var version: String {
        guard let ver = wgVersion() else { return "unknown" }
        return String(cString: ver)
    }
}

// MARK: - Example Usage

///// Example function to start the tunnel.
//func exampleStartTunnel() {
//    let manager = WireGuardTunnelManager()
//    manager.startTunnel { error in
//        if let error = error {
//            // Handle error appropriately
//            print("Start tunnel error: \(error)")
//        }
//    }
//}
//
///// Example function to stop the tunnel later.
//func exampleStopTunnel(manager: WireGuardTunnelManager) {
//    manager.stopTunnel { error in
//        if let error = error {
//            // Handle error appropriately
//            print("Stop tunnel error: \(error)")
//        }
//    }
//}
