//
//  ConnectionMonitor.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation
import Network

class ConnectionMonitor {
    private let keepAliveInterval: TimeInterval
    private var lastActivity: Date
    private var timer: Timer?
    private var pathMonitor: NWPathMonitor?
    private let queue: DispatchQueue
    
    var onConnectionLost: (() -> Void)?
    var onConnectionRestored: (() -> Void)?
    var onNetworkPathChanged: ((NWPath) -> Void)?
    
    private(set) var isConnected: Bool = false
    
    init(keepAliveInterval: TimeInterval,
         queue: DispatchQueue = DispatchQueue(label: "com.wireguard.monitor")) {
        self.keepAliveInterval = keepAliveInterval
        self.lastActivity = Date()
        self.queue = queue
    }
    
    func startMonitoring() {
        // Start activity timer
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkActivity()
        }
        
        // Start network path monitoring
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            self?.handlePathChange(path)
        }
        pathMonitor?.start(queue: queue)
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }
    
    func activityDetected() {
        lastActivity = Date()
        if !isConnected {
            isConnected = true
            onConnectionRestored?()
        }
    }
    
    private func checkActivity() {
        let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)
        if timeSinceLastActivity > keepAliveInterval && isConnected {
            isConnected = false
            onConnectionLost?()
        }
    }
    
    private func handlePathChange(_ path: NWPath) {
        onNetworkPathChanged?(path)
        
        switch path.status {
        case .satisfied:
            if !isConnected {
                isConnected = true
                onConnectionRestored?()
            }
        case .unsatisfied:
            if isConnected {
                isConnected = false
                onConnectionLost?()
            }
        default:
            break
        }
    }
}
