//
//  OperationStepsDefinition.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

struct ExecutionStep: Hashable {
    let step: OperationStep
    let weight: Int64

    init(_ step: OperationStep, _ weight: Int64) {
        self.step = step
        self.weight = weight
    }
}

struct OperationStepsDefinition {
    static let install: [ExecutionStep] = [
        ExecutionStep(.userCustomization, 2),
        ExecutionStep(.downloadApp, 20),
        ExecutionStep(.verifyApp, 1),
        ExecutionStep(.cacheApp, 1),
        ExecutionStep(.stageApp, 1),
        ExecutionStep(.patchAppIcon, 1),
        ExecutionStep(.removeAppExtensions, 1),
        ExecutionStep(.fetchAnisetteData, 5),
        ExecutionStep(.fetchProvisioningProfilesInstall, 5),
        ExecutionStep(.prepareAppExtensionBundleIDs, 1),
        ExecutionStep(.resignApp, 25),
        ExecutionStep(.exportResignedApp, 1),
        ExecutionStep(.sendApp, 20),
        ExecutionStep(.installApp, 15),
        ExecutionStep(.cleanStagedApp, 1)
    ]

    static let resign: [ExecutionStep] = [
        ExecutionStep(.stageApp, 2),
        ExecutionStep(.patchAppIcon, 2),
        ExecutionStep(.removeAppExtensions, 2),
        ExecutionStep(.fetchAnisetteData, 5),
        ExecutionStep(.fetchProvisioningProfilesInstall, 10),
        ExecutionStep(.prepareAppExtensionBundleIDs, 2),
        ExecutionStep(.resignApp, 30),
        ExecutionStep(.exportResignedApp, 2),
        ExecutionStep(.sendApp, 20),
        ExecutionStep(.installApp, 23),
        ExecutionStep(.cleanStagedApp, 2)
    ]

    static let refresh: [ExecutionStep] = [
        ExecutionStep(.fetchAnisetteData, 5),
        ExecutionStep(.fetchProvisioningProfilesRefresh, 55),
        ExecutionStep(.refreshApp, 40)
    ]

    static let activateLegacy: [ExecutionStep] = [
        ExecutionStep(.fetchAnisetteData, 5),
        ExecutionStep(.fetchProvisioningProfilesRefresh, 55),
        ExecutionStep(.refreshApp, 40)
    ]

    static let activate: [ExecutionStep] = [
        ExecutionStep(.installBackupApp, 5),
        ExecutionStep(.restoreApp, 10),
        ExecutionStep(.stageApp, 2),
        ExecutionStep(.patchAppIcon, 2),
        ExecutionStep(.removeAppExtensions, 2),
        ExecutionStep(.fetchAnisetteData, 5),
        ExecutionStep(.fetchProvisioningProfilesInstall, 5),
        ExecutionStep(.prepareAppExtensionBundleIDs, 1),
        ExecutionStep(.resignApp, 20),
        ExecutionStep(.exportResignedApp, 1),
        ExecutionStep(.sendApp, 15),
        ExecutionStep(.installApp, 25),
        ExecutionStep(.removeAppBackup, 5),
        ExecutionStep(.cleanStagedApp, 2)
    ]

    static let deactivateLegacy: [ExecutionStep] = [
        ExecutionStep(.deactivateApp, 100)
    ]

    static let deactivate: [ExecutionStep] = [
        ExecutionStep(.installBackupApp, 10),
        ExecutionStep(.backupApp, 60),
        ExecutionStep(.removeApp, 30)
    ]

    static let backup: [ExecutionStep] = [
        ExecutionStep(.installBackupApp, 10),
        ExecutionStep(.fetchAnisetteData, 5),
        ExecutionStep(.fetchProvisioningProfilesInstall, 5),
        ExecutionStep(.prepareAppExtensionBundleIDs, 5),
        ExecutionStep(.resignApp, 15),
        ExecutionStep(.exportResignedApp, 5),
        ExecutionStep(.sendApp, 10),
        ExecutionStep(.installApp, 15),
        ExecutionStep(.backupApp, 15),
        ExecutionStep(.stageApp, 2),
        ExecutionStep(.patchAppIcon, 2),
        ExecutionStep(.removeAppExtensions, 2),
        ExecutionStep(.removeAppBackup, 5),
        ExecutionStep(.cleanStagedApp, 4)
    ]

    static let restoreLegacy: [ExecutionStep] = [
        ExecutionStep(.fetchAnisetteData, 5),
        ExecutionStep(.fetchProvisioningProfilesRefresh, 55),
        ExecutionStep(.refreshApp, 40)
    ]

    static let restore: [ExecutionStep] = [
        ExecutionStep(.installBackupApp, 5),
        ExecutionStep(.restoreApp, 10),
        ExecutionStep(.stageApp, 2),
        ExecutionStep(.patchAppIcon, 2),
        ExecutionStep(.removeAppExtensions, 2),
        ExecutionStep(.fetchAnisetteData, 5),
        ExecutionStep(.fetchProvisioningProfilesInstall, 5),
        ExecutionStep(.prepareAppExtensionBundleIDs, 1),
        ExecutionStep(.resignApp, 20),
        ExecutionStep(.exportResignedApp, 1),
        ExecutionStep(.sendApp, 15),
        ExecutionStep(.installApp, 25),
        ExecutionStep(.removeAppBackup, 5),
        ExecutionStep(.cleanStagedApp, 2)
    ]

    static let remove: [ExecutionStep] = [
        ExecutionStep(.removeAppBackup, 30),
        ExecutionStep(.removeApp, 70)
    ]

    static let deleteApp: [ExecutionStep] = [
        ExecutionStep(.removeApp, 100)
    ]

    static let enableJIT: [ExecutionStep] = [
        ExecutionStep(.enableJIT, 100)
    ]

    static let authenticate: [ExecutionStep] = [
        ExecutionStep(.fetchAnisetteData, 10),
        ExecutionStep(.authentication, 80),
        ExecutionStep(.fetchAppIDs, 10)
    ]

    static let clearAppCache: [ExecutionStep] = [
        ExecutionStep(.clearAppCache, 100)
    ]

    static let scheduleExpirationWarningNotification: [ExecutionStep] = [
        ExecutionStep(.scheduleExpirationWarningNotification, 100)
    ]

    static func pipeline(for operation: AppOperation) -> [ExecutionStep] {
        switch operation {
            case .install, .update:
                return install
            case .resign:
                return resign
            case .refresh:
                return refresh
            case .activate:
                if UserDefaults.standard.isLegacyDeactivationSupported {
                    return activateLegacy
                } else {
                    return activate
                }
            case .deactivate:
                if UserDefaults.standard.isLegacyDeactivationSupported {
                    return deactivateLegacy
                } else {
                    return deactivate
                }
            case .backup:
                return backup
            case .restore:
                if UserDefaults.standard.isLegacyDeactivationSupported {
                    return restoreLegacy
                } else {
                    return restore
                }
            case .remove:
                return remove
            case .deleteApp:
                return deleteApp
            case .enableJIT:
                return enableJIT
        }
    }
}

extension Array where Element == ExecutionStep {
    static var authenticate:                        [ExecutionStep] { OperationStepsDefinition.authenticate                        }
    static var install:                             [ExecutionStep] { OperationStepsDefinition.install                             }
    static var resign:                              [ExecutionStep] { OperationStepsDefinition.resign                              }
    static var refresh:                             [ExecutionStep] { OperationStepsDefinition.refresh                             }
    static var activate:                            [ExecutionStep] { OperationStepsDefinition.activate                            }
    static var deactivate:                          [ExecutionStep] { OperationStepsDefinition.deactivate                          }
    static var backup:                              [ExecutionStep] { OperationStepsDefinition.backup                              }
    static var restore:                             [ExecutionStep] { OperationStepsDefinition.restore                             }
    static var remove:                              [ExecutionStep] { OperationStepsDefinition.remove                              }
    static var deleteApp:                           [ExecutionStep] { OperationStepsDefinition.deleteApp                           }
    static var enableJIT:                           [ExecutionStep] { OperationStepsDefinition.enableJIT                           }
    static var clearAppCache:                       [ExecutionStep] { OperationStepsDefinition.clearAppCache                       }
    static var scheduleExpirationWarningNotification: [ExecutionStep] { OperationStepsDefinition.scheduleExpirationWarningNotification }
}
