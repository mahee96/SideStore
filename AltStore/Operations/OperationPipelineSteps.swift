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
                        .backupApp,
                        .downloadApp,
                        .userCustomization,
                        .cacheApp,
                        .verifyApp,
                        .cacheApp,
                        .removeAppExtensions,
                        .fetchAnisetteData,
                        .fetchProvisioningProfilesInstall,
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
                        .removeApp
                    ]
                }
            case .backup:
                return [
                    .backupApp
                ]
            case .restore:
                return [
                    .backupApp,
                    .downloadApp,
                    .userCustomization,
                    .cacheApp,
                    .verifyApp,
                    .cacheApp,
                    .removeAppExtensions,
                    .fetchAnisetteData,
                    .fetchProvisioningProfilesInstall,
                    .patchAppIcon,
                    .resignApp,
                    .exportResignedApp,
                    .sendApp,
                    .installApp,
                    .removeAppBackup
                ]
            case .remove:
                return [
                    .removeAppBackup,
                    .removeApp
                ]
            case .enableJIT:
                return [
                    .enableJIT
                ]
        }
    }
}
