//
//  LoggerService.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import os.log
import WireGuardKit

class LoggerService {
    static let shared = LoggerService()
    private let subsystem = "com.sidestore.EmotionalDamage"
    
    private init() {}
    
    func createLogger(category: String) -> Logger {
        return Logger(subsystem: subsystem, category: category)
    }
}

extension Logger {
    func log(_ level: WireGuardLogLevel, message: String) {
        switch level {
        case .verbose:
            self.debug("\(message)")
        case .error:
            self.error("\(message)")
        }
    }
}
