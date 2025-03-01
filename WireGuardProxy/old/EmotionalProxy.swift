//
//  EmotionalProxy.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import Foundation

public class EmotionalProxy {
    private var socket: UDPSocket?
//    private var tunnel: WireGuardTunnel?
    private var tunnel: WireGuardTunnelManager?
    private var isRunning = false
    private var workItem: DispatchWorkItem?
    
    public static let shared = EmotionalProxy()
    private init() {}
    
    public func start(bindAddr: SocketAddress) -> DispatchWorkItem {
        print("Starting Emotional Proxy")
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.stop()
            print("EMP instructed to die")
        }
        
        do {
//            let tunnel = try WireGuardTunnel(
//                serverPrivateKey: try WireGuardConfigBuilder.readServerPrivateKey(),
//                clientPublicKey: try WireGuardConfigBuilder.readClientPublicKey()
//            )
            
            guard let tunFd = TunSocket(fd: 0).fd else {
                print("TUN adapter couldn't be setup")
                return workItem
            }
            
            let tunnel = try WireGuardTunnelManager(
                serverPrivateKey: try WireGuardConfigBuilder.readServerPrivateKey(),
                clientPublicKey: try WireGuardConfigBuilder.readClientPublicKey(),
                tunFd: tunFd
            )
            
            tunnel.startTunnel(completion: { error in
                print("Tunnel error: \(String(describing: error))")
                return
            })
            
            let socket = try UDPSocket()
            // Retry binding logic from Rust implementation
            var bindAttempts = 0
            while bindAttempts < 10 {
                do {
                    try socket.bind(to: bindAddr)
                    break
                } catch {
                    if case UDPSocket.SocketError.addressInUse = error {
                        print("EMP address in use, retrying...")
                        Thread.sleep(forTimeInterval: 0.05)
                        bindAttempts += 1
                        continue
                    }
                    throw error
                }
            }
            self.tunnel = tunnel
            self.workItem = workItem

            isRunning = true
            self.socket = socket
            print("Emotional Proxy started successfully")

        } catch {
            print("Failed to start Emotional Proxy: \(error.localizedDescription)")
        }
        
        return workItem
    }
    
    public func stop() {
        print("Stopping Emotional Proxy")
        isRunning = false
        socket = nil
        tunnel = nil
        workItem = nil
        print("Emotional Proxy stopped")
    }
}
