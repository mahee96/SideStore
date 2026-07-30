//
//  OperationEntitlements.swift
//  AltStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

struct OperationEntitlements {
    static let defaultAdditionalEntitlements: [ALTEntitlement: Any] = [
        .increasedDebuggingMemoryLimit  : ALTEntitlement.increasedDebuggingMemoryLimit,
        .increasedMemoryLimit           : ALTEntitlement.increasedMemoryLimit,
        .extendedVirtualAddressing      : ALTEntitlement.extendedVirtualAddressing
    ]
}
