//
//  OperationsLoggingControl.swift
//  SideStore
//
//  Created by Magesh K on 14/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

class OperationsLoggingControl {

    static func isStepLoggingEnabled(for step: some OperationStep) -> Bool {
        let key = udKey(for: step)
        return getLoggingValueInDb(key: key) ?? true
    }

    static func setStepLoggingEnabled(for step: some OperationStep, value: Bool) {
        let key = udKey(for: step)
        setLoggingState(key: key, value: value)
    }

    public static func isLoggingEnabled(for operation: any OperationLogging.Type) -> Bool {
        return true
    }

    private static func udKey(for step: some OperationStep) -> String {
        return "Step_\(step)"
    }
}

private extension OperationsLoggingControl {
    static func setLoggingState(key: String, value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func getLoggingValueInDb(key: String) -> Bool? {
        return UserDefaults.standard.value(forKey: key) as? Bool
    }
}

internal func getOperationsLogTag(level: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let timestamp = formatter.string(from: Date())
    return "\(timestamp) \(level): "
}
