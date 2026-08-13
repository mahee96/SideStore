//
//  UIColor+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

public extension UIColor
{
    private static func namedColor(_ name: String) -> UIColor? {
        return UIColor(named: name, in: Bundle.altStoreCore, compatibleWith: nil) ?? UIColor(named: name, in: .main, compatibleWith: nil)
    }

    static var altPrimary: UIColor {
        return ThemeManager.shared.primaryColor
    }
    static let defaultAltPrimary = namedColor("Primary")!
    static let deltaPrimary = namedColor("DeltaPrimary")
    static let clipPrimary = namedColor("ClipPrimary")
    
    static let refreshRed = namedColor("RefreshRed")!
    static let refreshOrange = namedColor("RefreshOrange")!
    static let refreshYellow = namedColor("RefreshYellow")!
    static let refreshGreen = namedColor("RefreshGreen")!
}
