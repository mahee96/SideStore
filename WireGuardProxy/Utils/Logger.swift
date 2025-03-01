//
//  Logger.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation
import os.log

class Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.wireguard"
    private static let log = OSLog(subsystem: subsystem, category: "WireGuardProxy")
    
    enum Level: String {
        case debug = "💬"
        case info = "ℹ️"
        case warning = "⚠️"
        case error = "❌"
        case critical = "🚨"
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }
    }
    
    static func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(level.rawValue) [\(fileName):\(line)] \(function) - \(message)"
        
        os_log("%{public}@", log: log, type: level.osLogType, logMessage)
        
        #if DEBUG
        print(logMessage)
        #endif
    }
    
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    static func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, file: file, function: function, line: line)
    }
}
