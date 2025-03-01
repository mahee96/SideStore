//
//  EmotionalDamage.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation

// C API interface
@_cdecl("start_emotional_damage")
public func start_emotional_damage(bindAddr: UnsafePointer<CChar>) -> Int32 {
    let logger = LoggerService.shared.createLogger(category: "EmotionalDamage")
    
    // Parse the address
    guard let addressStr = String(cString: bindAddr, encoding: .utf8),
          let socketAddress = SocketAddress(fromString: addressStr) else {
        return -2
    }
    
    // Start the proxy
    let _ = EmotionalProxy.shared.start(bindAddr: socketAddress)
    
    // Use a semaphore to wait briefly to see if the tunnel starts
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 1.0)
    
    // Check if successful
    return EmotionalProxy.shared.test(timeout: 500) ? 0 : -1
}

@_cdecl("stop_emotional_damage")
public func stop_emotional_damage() {
    EmotionalProxy.shared.stop()
}

@_cdecl("test_emotional_damage")
public func test_emotional_damage(timeout: Int32) -> Int32 {
    return EmotionalProxy.shared.test(timeout: timeout) ? 0 : -1
}

// Swift-friendly API
public class EmotionalDamage {
    public static func start(bindAddr: String) -> Bool {
        let cString = strdup(bindAddr)
        defer { free(cString) }
        return start_emotional_damage(bindAddr: cString!) == 0
    }
    
    public static func stop() {
        stop_emotional_damage()
    }
    
    public static func test(timeoutMs: Int32 = 1000) -> Bool {
        return test_emotional_damage(timeout: timeoutMs) == 0
    }
}
