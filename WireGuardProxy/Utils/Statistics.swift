//
//  TrafficStatistics.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation

class TrafficStatistics {
    private(set) var bytesReceived: UInt64 = 0
    private(set) var bytesSent: UInt64 = 0
    private(set) var packetsReceived: UInt64 = 0
    private(set) var packetsSent: UInt64 = 0
    
    func recordReceived(_ bytes: Int) {
        bytesReceived += UInt64(bytes)
        packetsReceived += 1
    }
    
    func recordSent(_ bytes: Int) {
        bytesSent += UInt64(bytes)
        packetsSent += 1
    }
}