//
//  UDPConnection.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation
import Network

class UDPConnection {
    private var connection: NWConnection?
    private let queue: DispatchQueue
    private var isRunning = false
    
    var onPacketReceived: ((Data, NWConnection.Context) -> Void)?
    
    init(queue: DispatchQueue = .init(label: "com.wireguard.network")) {
        self.queue = queue
    }
    
    func start(endpoint: NWEndpoint) async throws {
        // Implement connection setup
    }
    
    func send(_ packet: Data) async throws {
        // Implement packet sending
    }
    
    private func startReceiving() {
        // Implement packet receiving
    }
}

extension UDPConnection {
    func receiveWithTimeout(_ timeout: TimeInterval) async throws -> Data? {
        return try await withCheckedThrowingContinuation { continuation in
            let deadline = DispatchTime.now() + timeout
            
            connection?.receive(minimumIncompleteLength: 1, maximumLength: 65535) { content, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let content = content, isComplete {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            // Set up timeout
            queue.asyncAfter(deadline: deadline) {
                continuation.resume(returning: nil)
            }
        }
    }
}
