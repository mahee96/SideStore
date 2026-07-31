//
//  OperationStep.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

enum OperationStep: Hashable {
    case authentication
    case backupApp
    case backgroundRefreshApps
    case cacheApp
    case clearAppCache
    case deactivateApp
    case downloadApp
    case enableJIT
    case exportResignedApp
    case fetchAnisetteData
    case fetchAppIDs
    case fetchProvisioningProfilesInstall
    case fetchProvisioningProfilesRefresh
    case fetchSource
    case installApp
    case installBackupApp
    case patchAppIcon
    case refreshApp
    case restoreApp
    case prepareAppExtensionBundleIDs
    case removeAppBackup
    case removeAppExtensions
    case removeApp
    case resignApp
    case scheduleExpirationWarningNotification
    case sendApp
    case stageApp
    case userCustomization
    case preflightChecks
    case verifyApp
    case unknown

    private static let stepMap: [ObjectIdentifier: OperationStep] = [
        ObjectIdentifier(AuthenticationOperation.self): .authentication,
        ObjectIdentifier(BackupAppOperation.self): .backupApp,
        ObjectIdentifier(BackgroundRefreshAppsOperation.self): .backgroundRefreshApps,
        ObjectIdentifier(CacheAppOperation.self): .cacheApp,
        ObjectIdentifier(ClearAppCacheOperation.self): .clearAppCache,
        ObjectIdentifier(DeactivateAppOperation.self): .deactivateApp,
        ObjectIdentifier(DownloadAppOperation.self): .downloadApp,
        ObjectIdentifier(EnableJITOperation.self): .enableJIT,
        ObjectIdentifier(ExportResignedAppOperation.self): .exportResignedApp,
        ObjectIdentifier(FetchAnisetteDataOperation.self): .fetchAnisetteData,
        ObjectIdentifier(FetchAppIDsOperation.self): .fetchAppIDs,
        ObjectIdentifier(FetchProvisioningProfilesInstallOperation.self): .fetchProvisioningProfilesInstall,
        ObjectIdentifier(FetchProvisioningProfilesRefreshOperation.self): .fetchProvisioningProfilesRefresh,
        ObjectIdentifier(FetchSourceOperation.self): .fetchSource,
        ObjectIdentifier(InstallAppOperation.self): .installApp,
        ObjectIdentifier(InstallBackupAppOperation.self): .installBackupApp,
        ObjectIdentifier(PatchAppIconOperation.self): .patchAppIcon,
        ObjectIdentifier(RefreshAppOperation.self): .refreshApp,
        ObjectIdentifier(RemoveAppBackupOperation.self): .removeAppBackup,
        ObjectIdentifier(RemoveAppExtensionsOperation.self): .removeAppExtensions,
        ObjectIdentifier(RemoveAppOperation.self): .removeApp,
        ObjectIdentifier(ResignAppOperation.self): .resignApp,
        ObjectIdentifier(ScheduleExpirationWarningNotificationOperation.self): .scheduleExpirationWarningNotification,
        ObjectIdentifier(SendAppOperation.self): .sendApp,
        ObjectIdentifier(StageAppOperation.self): .stageApp,
        ObjectIdentifier(UserCustomizationOperation.self): .userCustomization,
        ObjectIdentifier(PreflightChecksOperation.self): .preflightChecks,
        ObjectIdentifier(VerifyAppOperation.self): .verifyApp
    ]

    static func step(for type: Any.Type) -> OperationStep {
        stepMap[ObjectIdentifier(type)] ?? .unknown
    }
}
