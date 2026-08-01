//
//  OperationStepsDefinition.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

struct PipelineExecutionStep: Hashable {
    let step: PipelineStep
    let weight: Int64

    init(_ step: PipelineStep, _ weight: Int64) {
        self.step = step
        self.weight = weight
    }
}

struct StandaloneExecutionStep: Hashable {
    let step: StandaloneStep
    let weight: Int64

    init(_ step: StandaloneStep, _ weight: Int64) {
        self.step = step
        self.weight = weight
    }
}

struct PipelineDefinition {
    static let install: [PipelineExecutionStep] = [
        PipelineExecutionStep(.userCustomization,                2),
        PipelineExecutionStep(.downloadApp,                     20),
        PipelineExecutionStep(.verifyApp,                       1),
        PipelineExecutionStep(.cacheApp,                        1),
        PipelineExecutionStep(.stageApp,                        1),
        PipelineExecutionStep(.patchAppIcon,                    1),
        PipelineExecutionStep(.removeAppExtensions,             1),
        PipelineExecutionStep(.fetchAnisetteData,               5),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 5),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,    1),
        PipelineExecutionStep(.resignApp,                       25),
        PipelineExecutionStep(.exportResignedApp,               1),
        PipelineExecutionStep(.sendApp,                         20),
        PipelineExecutionStep(.installApp,                      15),
        PipelineExecutionStep(.cleanStagedApp,                  1)
    ]

    static let resign: [PipelineExecutionStep] = [
        PipelineExecutionStep(.stageApp,                        2),
        PipelineExecutionStep(.patchAppIcon,                    2),
        PipelineExecutionStep(.removeAppExtensions,             2),
        PipelineExecutionStep(.fetchAnisetteData,               5),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 10),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,    2),
        PipelineExecutionStep(.resignApp,                       30),
        PipelineExecutionStep(.exportResignedApp,               2),
        PipelineExecutionStep(.sendApp,                         20),
        PipelineExecutionStep(.installApp,                      23),
        PipelineExecutionStep(.cleanStagedApp,                  2)
    ]

    static let refresh: [PipelineExecutionStep] = [
        PipelineExecutionStep(.fetchAnisetteData,                5),
        PipelineExecutionStep(.fetchProvisioningProfilesRefresh, 55),
        PipelineExecutionStep(.refreshApp,                       40)
    ]

    static let activateLegacy: [PipelineExecutionStep] = [
        PipelineExecutionStep(.fetchAnisetteData,                5),
        PipelineExecutionStep(.fetchProvisioningProfilesRefresh, 55),
        PipelineExecutionStep(.refreshApp,                       40)
    ]

    static let activate: [PipelineExecutionStep] = [
        PipelineExecutionStep(.installBackupApp,                 5),
        PipelineExecutionStep(.restoreApp,                       10),
        PipelineExecutionStep(.stageApp,                         2),
        PipelineExecutionStep(.patchAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,              2),
        PipelineExecutionStep(.fetchAnisetteData,                5),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 5),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,     1),
        PipelineExecutionStep(.resignApp,                        20),
        PipelineExecutionStep(.exportResignedApp,                1),
        PipelineExecutionStep(.sendApp,                          15),
        PipelineExecutionStep(.installApp,                       25),
        PipelineExecutionStep(.removeAppBackup,                  5),
        PipelineExecutionStep(.cleanStagedApp,                   2)
    ]

    static let deactivateLegacy: [PipelineExecutionStep] = [
        PipelineExecutionStep(.deactivateApp, 100)
    ]

    static let deactivate: [PipelineExecutionStep] = [
        PipelineExecutionStep(.installBackupApp, 10),
        PipelineExecutionStep(.backupApp,        60),
        PipelineExecutionStep(.removeApp,        30)
    ]

    static let backup: [PipelineExecutionStep] = [
        PipelineExecutionStep(.installBackupApp,                 10),
        PipelineExecutionStep(.fetchAnisetteData,                5),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 5),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,     5),
        PipelineExecutionStep(.resignApp,                        15),
        PipelineExecutionStep(.exportResignedApp,                5),
        PipelineExecutionStep(.sendApp,                          10),
        PipelineExecutionStep(.installApp,                       15),
        PipelineExecutionStep(.backupApp,                        15),
        PipelineExecutionStep(.stageApp,                         2),
        PipelineExecutionStep(.patchAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,              2),
        PipelineExecutionStep(.removeAppBackup,                  5),
        PipelineExecutionStep(.cleanStagedApp,                   4)
    ]

    static let restoreLegacy: [PipelineExecutionStep] = [
        PipelineExecutionStep(.fetchAnisetteData,                5),
        PipelineExecutionStep(.fetchProvisioningProfilesRefresh, 55),
        PipelineExecutionStep(.refreshApp,                       40)
    ]

    static let restore: [PipelineExecutionStep] = [
        PipelineExecutionStep(.installBackupApp,                 5),
        PipelineExecutionStep(.restoreApp,                       10),
        PipelineExecutionStep(.stageApp,                         2),
        PipelineExecutionStep(.patchAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,              2),
        PipelineExecutionStep(.fetchAnisetteData,                5),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 5),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,     1),
        PipelineExecutionStep(.resignApp,                        20),
        PipelineExecutionStep(.exportResignedApp,                1),
        PipelineExecutionStep(.sendApp,                          15),
        PipelineExecutionStep(.installApp,                       25),
        PipelineExecutionStep(.removeAppBackup,                  5),
        PipelineExecutionStep(.cleanStagedApp,                   2)
    ]

    static let remove: [PipelineExecutionStep] = [
        PipelineExecutionStep(.removeAppBackup, 30),
        PipelineExecutionStep(.removeApp,       70)
    ]

    static let deleteApp: [PipelineExecutionStep] = [
        PipelineExecutionStep(.removeApp, 100)
    ]

    static let enableJIT: [PipelineExecutionStep] = [
        PipelineExecutionStep(.enableJIT, 100)
    ]

    static func steps(for operation: AppOperation) -> [PipelineExecutionStep] {
        switch operation {
        case .install, .update:
            return install
        case .resign:
            return resign
        case .refresh:
            return refresh
        case .activate:
            return UserDefaults.standard.isLegacyDeactivationSupported ? activateLegacy : activate
        case .deactivate:
            return UserDefaults.standard.isLegacyDeactivationSupported ? deactivateLegacy : deactivate
        case .backup:
            return backup
        case .restore:
            return UserDefaults.standard.isLegacyDeactivationSupported ? restoreLegacy : restore
        case .remove:
            return remove
        case .deleteApp:
            return deleteApp
        case .enableJIT:
            return enableJIT
        }
    }
}

struct StandaloneDefinition {
    static let authenticate: [StandaloneExecutionStep] = [
        StandaloneExecutionStep(.fetchAnisetteData, 10),
        StandaloneExecutionStep(.authentication,    80),
        StandaloneExecutionStep(.fetchAppIDs,       10)
    ]

    static let backgroundRefreshApps: [StandaloneExecutionStep] = [
        StandaloneExecutionStep(.backgroundRefreshApps, 100)
    ]

    static let clearAppCache: [StandaloneExecutionStep] = [
        StandaloneExecutionStep(.clearAppCache, 100)
    ]

    static let scheduleExpirationWarningNotification: [StandaloneExecutionStep] = [
        StandaloneExecutionStep(.scheduleExpirationWarningNotification, 100)
    ]
}

extension Array where Element == PipelineExecutionStep {
    static var install:          [PipelineExecutionStep] { PipelineDefinition.install          }
    static var resign:           [PipelineExecutionStep] { PipelineDefinition.resign           }
    static var refresh:          [PipelineExecutionStep] { PipelineDefinition.refresh          }
    static var activate:         [PipelineExecutionStep] { PipelineDefinition.activate         }
    static var deactivate:       [PipelineExecutionStep] { PipelineDefinition.deactivate       }
    static var backup:           [PipelineExecutionStep] { PipelineDefinition.backup           }
    static var restore:          [PipelineExecutionStep] { PipelineDefinition.restore          }
    static var remove:           [PipelineExecutionStep] { PipelineDefinition.remove           }
    static var deleteApp:        [PipelineExecutionStep] { PipelineDefinition.deleteApp        }
    static var enableJIT:        [PipelineExecutionStep] { PipelineDefinition.enableJIT        }
}

extension Array where Element == StandaloneExecutionStep {
    static var authenticate:                          [StandaloneExecutionStep] { StandaloneDefinition.authenticate                          }
    static var backgroundRefreshApps:                 [StandaloneExecutionStep] { StandaloneDefinition.backgroundRefreshApps                 }
    static var clearAppCache:                         [StandaloneExecutionStep] { StandaloneDefinition.clearAppCache                         }
    static var scheduleExpirationWarningNotification: [StandaloneExecutionStep] { StandaloneDefinition.scheduleExpirationWarningNotification }
}
