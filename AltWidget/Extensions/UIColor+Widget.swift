//
//  UIColor+Widget.swift
//  AltWidget
//
//  Created by Magesh K on 8/13/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

extension UIColor {
    static var altPrimary: UIColor {
        UIColor(named: "Primary") ?? .systemBlue
    }

    static var deltaPrimary: UIColor? {
        UIColor(named: "DeltaPrimary")
    }

    static var clipPrimary: UIColor? {
        UIColor(named: "ClipPrimary")
    }

    convenience init?(hexString: String) {
        var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
