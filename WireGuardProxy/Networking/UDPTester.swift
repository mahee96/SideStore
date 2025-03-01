//
//  UDPTester.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

class UDPTester {
    static func testConnection(timeoutMs: Int) -> Bool {
        print("Testing UDP connection")
        
        // Find an available testing port
        var testingPort: UInt16 = 3000
        var listener: UDPSocket?
        
        // Try to bind to an available port
        while testingPort < 3100 {
            do {
                let socket = try UDPSocket()
                try socket.bind(to: SocketAddress(host: "127.0.0.1", port: Int(testingPort)))
                listener = socket
                break
            } catch {
                if case UDPSocket.SocketError.addressInUse = error {
                    testingPort += 1
                    continue
                }
                print("Unable to bind to UDP socket: \(error)")
                return false
            }
        }
        
        guard let listener = listener else {
            print("Failed to create listener socket")
            return false
        }
        
        // Create sender socket
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let sender = try UDPSocket()
                try sender.bind(to: SocketAddress(host: "127.0.0.1", port: Int(testingPort + 1)))
                
                // Send test packets
                for _ in 0..<10 {
                    try? sender.sendTo([69], endpoint: SocketAddress(host: "127.0.0.1", port: Int(testingPort)))
                    Thread.sleep(forTimeInterval: 0.001) // 1ms delay between sends
                }
            } catch {
                print("Sender socket error: \(error)")
            }
        }
        
        // Wait for test packet
        do {
            try listener.setReadTimeout(milliseconds: Int32(timeoutMs))
            var buf = [UInt8](repeating: 0, count: 1)
            let _ = try listener.receiveFrom(&buf)
            print("UDP test successful")
            return true
        } catch {
            print("Never received test data: \(error)")
            return false
        }
    }
} 
