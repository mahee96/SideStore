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
                    .downloadApp,
                    .userCustomization,
                    .cacheApp,
                    .verifyApp,
                    .cacheApp,
                    .removeAppExtensions,
                    .fetchAnisetteData,
                    .fetchProvisioningProfilesInstall,
                    .prepareAppExtensionBundleIDs,
                    .patchAppIcon,
                    .resignApp,
                    .exportResignedApp,
                    .sendApp,
                    .installApp,
                ]
            case .resign:
                return [
                    .userCustomization,
                    .verifyApp,
                    .removeAppExtensions,
                    .fetchAnisetteData,
                    .fetchProvisioningProfilesInstall,
                    .prepareAppExtensionBundleIDs,
                    .patchAppIcon,
                    .resignApp,
                    .exportResignedApp,
                    .sendApp,
                    .installApp
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
                        .downloadApp,
                        .userCustomization,
                        .cacheApp,
                        .verifyApp,
                        .cacheApp,
                        .removeAppExtensions,
                        .fetchAnisetteData,
                        .fetchProvisioningProfilesInstall,
                        .prepareAppExtensionBundleIDs,
                        .patchAppIcon,
                        .resignApp,
                        .exportResignedApp,
                        .sendApp,
                        .installApp,
                        .removeAppBackup
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
                    .backupApp
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
                        .downloadApp,
                        .userCustomization,
                        .cacheApp,
                        .verifyApp,
                        .cacheApp,
                        .removeAppExtensions,
                        .fetchAnisetteData,
                        .fetchProvisioningProfilesInstall,
                        .prepareAppExtensionBundleIDs,
                        .patchAppIcon,
                        .resignApp,
                        .exportResignedApp,
                        .sendApp,
                        .installApp,
                        .removeAppBackup
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
