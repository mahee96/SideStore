//
//  OperationStep.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

protocol OperationStep: Hashable {}

enum PipelineStep: OperationStep {
    case backupApp
    case cacheApp
    case cleanStagedApp
    case deactivateApp
    case downloadApp
    case enableJIT
    case exportResignedApp
    case fetchAnisetteData
    case fetchProvisioningProfilesInstall
    case fetchProvisioningProfilesRefresh
    case installApp
    case installBackupApp
    case patchAppIcon
    case prepareAppExtensionBundleIDs
    case preflightChecks
    case refreshApp
    case removeApp
    case removeAppBackup
    case removeAppExtensions
    case resignApp
    case restoreApp
    case sendApp
    case stageApp
    case userCustomization
    case verifyApp

    private static let stepMap: [ObjectIdentifier: PipelineStep] = [
        ObjectIdentifier(BackupAppOperation.self):                        .backupApp,
        ObjectIdentifier(CacheAppOperation.self):                         .cacheApp,
        ObjectIdentifier(CleanStagedAppOperation.self):                   .cleanStagedApp,
        ObjectIdentifier(DeactivateAppOperation.self):                    .deactivateApp,
        ObjectIdentifier(DownloadAppOperation.self):                      .downloadApp,
        ObjectIdentifier(EnableJITOperation.self):                        .enableJIT,
        ObjectIdentifier(ExportResignedAppOperation.self):                .exportResignedApp,
        ObjectIdentifier(FetchAnisetteDataOperation.self):                .fetchAnisetteData,
        ObjectIdentifier(FetchProvisioningProfilesInstallOperation.self): .fetchProvisioningProfilesInstall,
        ObjectIdentifier(FetchProvisioningProfilesRefreshOperation.self): .fetchProvisioningProfilesRefresh,
        ObjectIdentifier(InstallAppOperation.self):                       .installApp,
        ObjectIdentifier(InstallBackupAppOperation.self):                 .installBackupApp,
        ObjectIdentifier(PatchAppIconOperation.self):                     .patchAppIcon,
        ObjectIdentifier(PrepareAppExtensionBundleIDsOperation.self):     .prepareAppExtensionBundleIDs,
        ObjectIdentifier(PreflightChecksOperation.self):                  .preflightChecks,
        ObjectIdentifier(RefreshAppOperation.self):                       .refreshApp,
        ObjectIdentifier(RemoveAppBackupOperation.self):                  .removeAppBackup,
        ObjectIdentifier(RemoveAppExtensionsOperation.self):              .removeAppExtensions,
        ObjectIdentifier(RemoveAppOperation.self):                        .removeApp,
        ObjectIdentifier(ResignAppOperation.self):                        .resignApp,
//        ObjectIdentifier(RestoreAppOperation.self):                       .restoreApp,
        ObjectIdentifier(SendAppOperation.self):                          .sendApp,
        ObjectIdentifier(StageAppOperation.self):                         .stageApp,
        ObjectIdentifier(UserCustomizationOperation.self):                .userCustomization,
        ObjectIdentifier(VerifyAppOperation.self):                        .verifyApp,
    ]

    static func step(for type: Any.Type) -> PipelineStep? {
        stepMap[ObjectIdentifier(type)]
    }
}

enum StandaloneStep: OperationStep {
    case authentication
    case backgroundRefreshApps
    case clearAppCache
    case fetchAnisetteData
    case fetchAppIDs
    case fetchSource
    case scheduleExpirationWarningNotification
    case unknown

    private static let stepMap: [ObjectIdentifier: StandaloneStep] = [
        ObjectIdentifier(AuthenticationOperation.self):                          .authentication,
        ObjectIdentifier(BackgroundRefreshAppsOperation.self):                   .backgroundRefreshApps,
        ObjectIdentifier(ClearAppCacheOperation.self):                           .clearAppCache,
        ObjectIdentifier(FetchAnisetteDataOperation.self):                       .fetchAnisetteData,
        ObjectIdentifier(SyncAppIDsOperation.self):                              .fetchAppIDs,
        ObjectIdentifier(FetchSourceOperation.self):                             .fetchSource,
        ObjectIdentifier(ScheduleExpirationWarningNotificationOperation.self):   .scheduleExpirationWarningNotification,
    ]

    static func step(for type: Any.Type) -> StandaloneStep? {
        stepMap[ObjectIdentifier(type)] ?? .unknown
    }
}
