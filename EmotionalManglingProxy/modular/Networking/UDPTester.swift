//
//  UDPTester.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation

class UDPTester {
    private static let logger = LoggerService.shared.createLogger(category: "UDPTester")
    
    static func testConnection(timeoutMs: Int) -> Bool {
        // Bind to a testing socket
        var testingPort: UInt16 = 3000
        var listener: UDPSocket?
        
        repeat {
            do {
                listener = try UDPSocket(port: testingPort)
                break
            } catch {
                testingPort += 1
            }
        } while testingPort < 4000
        
        guard let socket = listener else {
            logger.error("Unable to bind to UDP socket")
            return false
        }
        
        // Set timeout
        socket.setTimeout(timeoutMs)
        
        // Create a sender socket for testing
        DispatchQueue.global().async {
            do {
                let sender = try UDPSocket(port: testingPort + 1)
                
                // Send test data
                for _ in 0..<10 {
                    do {
                        try sender.send(data: Data([69]), to: "127.0.0.1", port: testingPort)
                    } catch {
                        logger.error("Failed to send test packet: \(error.localizedDescription)")
                    }
                    Thread.sleep(forTimeInterval: 0.001) // 1ms delay between sends
                }
            } catch {
                logger.error("Failed to create sender socket: \(error.localizedDescription)")
            }
        }
        
        // Try to receive data
        do {
            let _ = try socket.receive(timeout: timeoutMs)
            return true
        } catch {
            logger.error("Never received test data: \(error.localizedDescription)")
            return false
        }
    }
}
