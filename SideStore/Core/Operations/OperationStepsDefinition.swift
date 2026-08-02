//
//  OperationStepsDefinition.swift
//  SideStore
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
        PipelineExecutionStep(.changeAppIcon,                    1),
        PipelineExecutionStep(.removeAppExtensions,              6),
        PipelineExecutionStep(.updateAppCertificate,            5),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 15),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,    1),
        PipelineExecutionStep(.resignApp,                       15),
        PipelineExecutionStep(.exportResignedApp,               1),
        PipelineExecutionStep(.sendApp,                         20),
        PipelineExecutionStep(.installApp,                      15),
        PipelineExecutionStep(.cleanStagedApp,                  1)
    ]

    static let resign: [PipelineExecutionStep] = [
        PipelineExecutionStep(.stageApp,                        2),
        PipelineExecutionStep(.changeAppIcon,                    2),
        PipelineExecutionStep(.removeAppExtensions,             7),
        PipelineExecutionStep(.updateAppCertificate,            5),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 20),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,    2),
        PipelineExecutionStep(.resignApp,                       20),
        PipelineExecutionStep(.exportResignedApp,               2),
        PipelineExecutionStep(.sendApp,                         20),
        PipelineExecutionStep(.installApp,                      23),
        PipelineExecutionStep(.cleanStagedApp,                  2)
    ]

    static let refresh: [PipelineExecutionStep] = [
        PipelineExecutionStep(.updateAppCertificate,            5),
        PipelineExecutionStep(.fetchProvisioningProfilesRefresh, 50),
        PipelineExecutionStep(.verifyCertificate,               10),
        PipelineExecutionStep(.refreshApp,                      40)
    ]

    static let activateLegacy: [PipelineExecutionStep] = [
        PipelineExecutionStep(.updateAppCertificate,            5),
        PipelineExecutionStep(.fetchProvisioningProfilesRefresh, 50),
        PipelineExecutionStep(.verifyCertificate,               10),
        PipelineExecutionStep(.refreshApp,                      40)
    ]

    static let activate: [PipelineExecutionStep] = [
        PipelineExecutionStep(.stageBackupApp,                 5),
        PipelineExecutionStep(.restoreAppData,                       10),
        PipelineExecutionStep(.stageApp,                         2),
        PipelineExecutionStep(.changeAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,              2),
        PipelineExecutionStep(.updateAppCertificate,            5),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 10),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,     1),
        PipelineExecutionStep(.resignApp,                        20),
        PipelineExecutionStep(.exportResignedApp,                1),
        PipelineExecutionStep(.sendApp,                          15),
        PipelineExecutionStep(.installApp,                       25),
        PipelineExecutionStep(.removeBackupData,                  5),
        PipelineExecutionStep(.cleanStagedApp,                   2)
    ]

    static let deactivateLegacy: [PipelineExecutionStep] = [
        PipelineExecutionStep(.deactivateApp, 100)
    ]

    static let deactivate: [PipelineExecutionStep] = [
        PipelineExecutionStep(.stageBackupApp, 10),
        PipelineExecutionStep(.backupAppData,        60),
        PipelineExecutionStep(.removeApp,        30)
    ]

    static let backup: [PipelineExecutionStep] = [
        PipelineExecutionStep(.stageBackupApp,                 10),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 10),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,     5),
        PipelineExecutionStep(.resignApp,                        10),
        PipelineExecutionStep(.exportResignedApp,                5),
        PipelineExecutionStep(.sendApp,                          10),
        PipelineExecutionStep(.installApp,                       10),
        PipelineExecutionStep(.backupAppData,                    30),  // must run BEFORE installApp wipes the container
        PipelineExecutionStep(.stageApp,                         2),
        PipelineExecutionStep(.changeAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,              2),
        PipelineExecutionStep(.cleanStagedApp,                   4)
    ]

    static let restoreLegacy: [PipelineExecutionStep] = [
        PipelineExecutionStep(.fetchProvisioningProfilesRefresh, 50),
        PipelineExecutionStep(.verifyCertificate,               10),
        PipelineExecutionStep(.refreshApp,                      40)
    ]

    static let restore: [PipelineExecutionStep] = [
        PipelineExecutionStep(.stageBackupApp,                 5),
        PipelineExecutionStep(.restoreAppData,                       10),
        PipelineExecutionStep(.stageApp,                         2),
        PipelineExecutionStep(.changeAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,              2),
        PipelineExecutionStep(.fetchProvisioningProfilesInstall, 10),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,     1),
        PipelineExecutionStep(.resignApp,                        20),
        PipelineExecutionStep(.exportResignedApp,                1),
        PipelineExecutionStep(.sendApp,                          15),
        PipelineExecutionStep(.installApp,                       25),
        PipelineExecutionStep(.removeBackupData,                  5),
        PipelineExecutionStep(.cleanStagedApp,                   2)
    ]

    static let remove: [PipelineExecutionStep] = [
        PipelineExecutionStep(.removeBackupData, 30),
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
