//
//  CellularRefreshManager.swift
//  SideStore
//
//  Created by Magesh K on 4/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import UIKit

public final class CellularRefreshManager: @unchecked Sendable {
    public static let shared = CellularRefreshManager()

    private let lock = NSLock()
    private var _didTurnOffData = false
    public var didTurnOffData: Bool {
        get { lock.withLock { _didTurnOffData } }
        set { lock.withLock { _didTurnOffData = newValue } }
    }

    private init() {}

    public var isSupported: Bool {
        #if os(tvOS)
        return false
        #else
        return true
        #endif
    }

    private var isEnabled: Bool {
        return UserDefaults.standard.isCellularRefreshEnabled
    }

    @MainActor
    private func openShortcut(url: URL) async -> Bool {
        debugLog("[CellularRefreshManager] Opening shortcut URL: \(url.absoluteString)")
        let success = await UIApplication.shared.open(url)
        debugLog("[CellularRefreshManager] Shortcut URL open completed with success: \(success)")
        return success
    }

    @discardableResult
    private func turnOffData() async -> Bool {
        debugLog("[CellularRefreshManager] Executing TurnOffData shortcut...")
        let success = await openShortcut(url: AppConstants.Shortcuts.turnOffDataURL)
        debugLog("[CellularRefreshManager] TurnOffData shortcut finished execution.")
        return success
    }

    @discardableResult
    private func turnOnData() async -> Bool {
        debugLog("[CellularRefreshManager] Executing turnOnData shortcut...")
        let success = await openShortcut(url: AppConstants.Shortcuts.turnOnDataURL)
        debugLog("[CellularRefreshManager] turnOnData shortcut finished execution.")
        return success
    }

    // public apis
    @discardableResult
    public func turnOffDataIfNeeded() async -> Bool {
        guard isSupported && isEnabled else { return false }
        let success = await turnOffData()
        if success {
            didTurnOffData = true
        }
        return success
    }

    @discardableResult
    public func turnOnDataIfNeeded() async -> Bool {
        guard didTurnOffData else { return false }
        let success = await turnOnData()
        if success {
            didTurnOffData = false
        }
        return success
    }
}
