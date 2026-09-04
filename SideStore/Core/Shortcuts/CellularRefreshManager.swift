//
//  CellularRefreshManager.swift
//  SideStore
//
//  Created by Magesh K on 4/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import UIKit
import Network

public final class CellularRefreshManager: @unchecked Sendable {
    public static let shared = CellularRefreshManager()

    private let lock = NSLock()
    private var cachedDidTurnOffData = false
    public var didTurnOffData: Bool {
        get { lock.withLock { cachedDidTurnOffData } }
        set { lock.withLock { cachedDidTurnOffData = newValue } }
    }

    private var cachedIsCellularActive = false
    public var isCellularActive: Bool {
        lock.withLock { cachedIsCellularActive }
    }

    private var cellularMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.sidestore.cellular.monitor", qos: .utility)
    private var isMonitoring = false

    private init() {}

    public var isSupported: Bool {
        #if os(tvOS)
        return false
        #else
        return true
        #endif
    }

    public var isEnabled: Bool {
        return UserDefaults.standard.isCellularRefreshEnabled
    }

    public func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.isCellularRefreshEnabled = enabled
        startMonitorIfRequired()
        if enabled {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    public func startMonitorIfRequired() {
        #if !os(tvOS)
        lock.withLock {
            guard isEnabled else {
                if isMonitoring {
                    cellularMonitor?.cancel()
                    cellularMonitor = nil
                    isMonitoring = false
                    cachedIsCellularActive = false
                    debugLog("[CellularRefreshManager] Cellular refresh disabled, stopped monitor.")
                }
                return
            }

            guard !isMonitoring else { return }

            let monitor = NWPathMonitor(requiredInterfaceType: .cellular)
            cachedIsCellularActive = (monitor.currentPath.status == .satisfied)
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                let isSatisfied = (path.status == .satisfied)
                self.lock.withLock {
                    self.cachedIsCellularActive = isSatisfied
                }
                debugLog("[CellularRefreshManager] Cellular path updated: isSatisfied=\(isSatisfied), didTurnOffData=\(self.didTurnOffData)")
            }
            monitor.start(queue: monitorQueue)
            self.cellularMonitor = monitor
            self.isMonitoring = true
            debugLog("[CellularRefreshManager] Started cellular path monitor.")
        }
        #endif
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
        guard !didTurnOffData else { return false }

        startMonitorIfRequired()

        // Check nw monitor tracked state: only turn off if cellular is active
        guard isCellularActive else {
            debugLog("[CellularRefreshManager] Cellular data is already off or inactive, skipping turnOff.")
            return false
        }

        let success = await turnOffData()
        if success {
            didTurnOffData = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return success
    }

    @discardableResult
    public func turnOnDataIfNeeded() async -> Bool {
        guard didTurnOffData else { return false }

        // Check if target state was already achieved externally
        if isCellularActive {
            debugLog("[CellularRefreshManager] Cellular data is already active externally, skipping turnOn.")
            didTurnOffData = false
            return true
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
        let success = await turnOnData()
        if success {
            didTurnOffData = false
        }
        return success
    }
}
