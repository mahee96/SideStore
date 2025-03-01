//
//  SocketAddress.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation

public struct SocketAddress {
    let host: String
    let port: Int
    
    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
    
    init?(fromString addressString: String) {
        let components = addressString.split(separator: ":")
        guard components.count == 2,
              let host = components.first,
              let port = UInt16(components.last!) else {
            return nil
        }
        
        self.host = String(host)
        self.port = Int(port)
    }
}