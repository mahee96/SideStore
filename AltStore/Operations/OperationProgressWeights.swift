//
//  OperationProgressWeights.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

struct OperationProgressWeights {
    static let install: [OperationStep: Int64] = [
        .downloadApp: 20,
        .userCustomization: 2,
        .fetchProvisioningProfilesInstall: 5,
        .resignApp: 20,
        .sendApp: 15,
        .installApp: 18
    ]

    static let resign: [OperationStep: Int64] = [
        .userCustomization: 2,
        .fetchProvisioningProfilesInstall: 10,
        .resignApp: 30,
        .sendApp: 20,
        .installApp: 18
    ]

    static let refresh: [OperationStep: Int64] = [
        .fetchProvisioningProfilesRefresh: 48,
        .refreshApp: 32
    ]

    static let authenticate: [OperationStep: Int64] = [
        .fetchAnisetteData: 1,
        .authentication: 1,
        .fetchAppIDs: 1
    ]

    static func forOperation(_ operation: AppOperation) -> [OperationStep: Int64] {
        switch operation {
            case .install, .update:
                return install
            case .resign:
                return resign
            case .refresh:
                return refresh
            default:
                return [:]
        }
    }
}
