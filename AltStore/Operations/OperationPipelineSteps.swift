//
//  OperationPipelineSteps.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

struct OperationPipelineSteps {
    static func steps(for operation: AppOperation) -> [OperationStep] {
        switch operation {
            case .install, .update:
                return [
                    .userCustomization,
                    .downloadApp,
                    .verifyApp,
                    .cacheApp,
                    .stageApp,
                    .patchAppIcon,
                    .removeAppExtensions,
                    .fetchAnisetteData,
                    .fetchProvisioningProfilesInstall,
                    .prepareAppExtensionBundleIDs,
                    .resignApp,
                    .exportResignedApp,
                    .sendApp,
                    .installApp,
                    .cleanStagedApp
                ]
            case .resign:
                return [
                    .stageApp,
                    .patchAppIcon,
                    .removeAppExtensions,
                    .fetchAnisetteData,
                    .fetchProvisioningProfilesInstall,
                    .prepareAppExtensionBundleIDs,
                    .resignApp,
                    .exportResignedApp,
                    .sendApp,
                    .installApp,
                    .cleanStagedApp
                ]
            case .refresh:
                return [
                    .fetchAnisetteData,
                    .fetchProvisioningProfilesRefresh,
                    .refreshApp
                ]
            case .activate:
                if UserDefaults.standard.isLegacyDeactivationSupported {
                    return [
                        .fetchAnisetteData,
                        .fetchProvisioningProfilesRefresh,
                        .refreshApp
                    ]
                } else {
                    return [
                        .installBackupApp,
                        .restoreApp,
                        .stageApp,
                        .patchAppIcon,
                        .removeAppExtensions,
                        .fetchAnisetteData,
                        .fetchProvisioningProfilesInstall,
                        .prepareAppExtensionBundleIDs,
                        .resignApp,
                        .exportResignedApp,
                        .sendApp,
                        .installApp,
                        .removeAppBackup,
                        .cleanStagedApp
                    ]
                }
            case .deactivate:
                if UserDefaults.standard.isLegacyDeactivationSupported {
                    return [
                        .deactivateApp
                    ]
                } else {
                    return [
                        .installBackupApp,
                        .backupApp,
                        .removeApp
                    ]
                }
            case .backup:
                return [
                    .installBackupApp,
                    .backupApp,
                    .restoreApp,
                    .stageApp,
                    .patchAppIcon,
                    .removeAppExtensions,
                    .fetchAnisetteData,
                    .fetchProvisioningProfilesInstall,
                    .prepareAppExtensionBundleIDs,
                    .resignApp,
                    .exportResignedApp,
                    .sendApp,
                    .installApp,
                    .removeAppBackup,
                    .cleanStagedApp
                ]
            case .restore:
                if UserDefaults.standard.isLegacyDeactivationSupported {
                    return [
                        .fetchAnisetteData,
                        .fetchProvisioningProfilesRefresh,
                        .refreshApp
                    ]
                } else {
                    return [
                        .installBackupApp,
                        .restoreApp,
                        .stageApp,
                        .patchAppIcon,
                        .removeAppExtensions,
                        .fetchAnisetteData,
                        .fetchProvisioningProfilesInstall,
                        .prepareAppExtensionBundleIDs,
                        .resignApp,
                        .exportResignedApp,
                        .sendApp,
                        .installApp,
                        .removeAppBackup,
                        .cleanStagedApp
                    ]
                }
            case .remove:
                return [
                    .removeAppBackup,
                    .removeApp
                ]
            case .deleteApp:
                return [
                    .removeApp
                ]
            case .enableJIT:
                return [
                    .enableJIT
                ]
        }
    }
}
