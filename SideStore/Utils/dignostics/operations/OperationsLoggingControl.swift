//
//  OperationsLoggingControl.swift
//  AltStore
//
//  Created by Magesh K on 14/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

class OperationsLoggingControl {

    func setLoggingEnabled(for operation: any OperationLogging.Type, value: Bool) {
        Self.setLoggingEnabled(for: operation, value: value)
    }
   
    private static func setLoggingEnabled(for operation: any OperationLogging.Type, value: Bool) {
        // This method should handle the database update logic based on the operation and value
        let key = Self.getKey(operation)
        debugLog("Updating database for key: \(key), value: \(value)")
        setOperationLoggingState(key: key, value: value)
    }
    
    private static func stripGenericTypeName(from string: String) -> String {
        // ex: 1. "EnableJITOperation<DummyConformance>"
        // ex: 1. "EnableJITOperation<DummyConformance<SomeMoreType>>"
        // will become EnableJITOperation without the generics type info
        if let range = string.range(of: "<") {
            return String(string[..<range.lowerBound])
        }
        return string
    }
    
    private static func getKey(_ operation: any OperationLogging.Type) -> String {
        let processedOperation = Self.stripGenericTypeName(from: "\(operation)")
        return "\(processedOperation)LoggingEnabled"
    }
    
    func isLoggingEnabled(for operation: any OperationLogging.Type)  -> Bool{
        return Self.isLoggingEnabled(for: operation)
    }

    static func getUpdatedFromDatabase(for operation: any OperationLogging.Type, defaultVal: Bool)  -> Bool{
        let key = Self.getKey(operation)
        let valueInDb = getOperationLoggingValueInDb(key: key)
        if valueInDb == nil {
            // put the value if not already present
            setLoggingEnabled(for: operation, value: defaultVal)
        }
        return valueInDb ?? defaultVal
    }

    public static func isLoggingEnabled(for operation: any OperationLogging.Type) -> Bool {
        let key = Self.getKey(operation)
        return getOperationLoggingBool(key: key)
    }
}

// MARK: - Private OperationsLoggingControl Persistence Extension

private extension OperationsLoggingControl {
    static func setOperationLoggingState(key: String, value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
    
    static func getOperationLoggingValueInDb(key: String) -> Bool? {
        return UserDefaults.standard.value(forKey: key) as? Bool
    }
    
    static func getOperationLoggingBool(key: String) -> Bool {
        return UserDefaults.standard.bool(forKey: key)
    }
}

internal func getOperationsLogTag(level: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let timestamp = formatter.string(from: Date())
    return "\(timestamp) \(level): "
}
