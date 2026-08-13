//
//  Bundle+AltStoreCore.swift
//  AltStoreCore
//
//  Created by Magesh K on 8/13/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

private final class AltStoreCoreBundleMarker {}

public extension Bundle {
    static var altStoreCore: Bundle {
        Bundle(for: AltStoreCoreBundleMarker.self)
    }
}
