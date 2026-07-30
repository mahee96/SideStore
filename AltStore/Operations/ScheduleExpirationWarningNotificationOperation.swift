//
//  ScheduleExpirationWarningNotificationOperation.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import UserNotifications
import Foundation
@preconcurrency import AltStoreCore

final class ScheduleExpirationWarningNotificationOperation: BaseOperation<OperationContext, Bool>, @unchecked Sendable {
    let installedApp: InstalledApp

    init(installedApp: InstalledApp, context: OperationContext) throws {
        self.installedApp = installedApp
        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> Bool {
        try await super.executePreconditionCheck(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)

        let center = UNUserNotificationCenter.current()
        let now = Date()
        let expirationDate = installedApp.expirationDate

        let milestones: [(id: String, timeBeforeExp: TimeInterval, title: String, body: String)] = [
            ("24h", 24 * 60 * 60, "SideStore Expiring Soon", "SideStore will expire in 24 hours. Open the app and refresh it to prevent it from expiring."),
            ("6h",   6 * 60 * 60, "SideStore Expiring Extremely Soon", "SideStore will expire in 6 hours! Refresh now to prevent expiration."),
            ("0h",   0,           "SideStore Expired", "SideStore has expired. Please refresh or reinstall the app.")
        ]

        let allIdentifiers = milestones.map { "\(AppManager.expirationWarningNotificationID).\($0.id)" }
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)

        for milestone in milestones {
            let identifier = "\(AppManager.expirationWarningNotificationID).\(milestone.id)"
            let targetDate = expirationDate.addingTimeInterval(-milestone.timeBeforeExp)
            let triggerInterval = targetDate.timeIntervalSince(now)

            // Skip milestones that are already in the past
            guard triggerInterval > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString(milestone.title, comment: "")
            content.body = NSLocalizedString(milestone.body, comment: "")
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerInterval, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            try await center.add(request)
        }
        return true
    }
}
