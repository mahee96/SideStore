//
//  String+Localization.swift
//  SideStore
//
//  Created by Magesh K on 12/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

@inline(__always)
public func localized(_ value: String.LocalizationValue) -> String {
    String(localized: value)
}

@inline(__always)
public func localized(_ value: String.LocalizationValue, comment: StaticString) -> String {
    String(localized: value, comment: comment)
}
