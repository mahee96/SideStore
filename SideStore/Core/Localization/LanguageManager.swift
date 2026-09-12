//
//  LanguageManager.swift
//  SideStore
//
//  Created by Magesh K on 12/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case korean = "ko"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .system:
            return "System"
        case .english:
            return "English"
        case .korean:
            return "한국어"
        }
    }
}

public final class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()
    
    @Published public var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.selectedAppLanguage = selectedLanguage.rawValue
            updateBundleOverride()
        }
    }
    
    @Published public private(set) var effectiveLanguageCode: String = "en"
    
    public var locale: Locale {
        Locale(identifier: effectiveLanguageCode)
    }
    
    private init() {
        let saved = UserDefaults.standard.selectedAppLanguage ?? AppLanguage.system.rawValue
        let initial = AppLanguage(rawValue: saved) ?? .system
        self.selectedLanguage = initial
        self.effectiveLanguageCode = LanguageManager.resolveEffectiveLanguageCode(for: initial)
        self.updateBundleOverride()
    }
    
    private static func resolveEffectiveLanguageCode(for language: AppLanguage) -> String {
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            if preferred.hasPrefix("ko") {
                return "ko"
            }
            return "en"
        case .english:
            return "en"
        case .korean:
            return "ko"
        }
    }
    
    private func updateBundleOverride() {
        let code = LanguageManager.resolveEffectiveLanguageCode(for: selectedLanguage)
        effectiveLanguageCode = code
        LocalizedBundleHelper.setCurrentLanguage(code)
    }
}

private var bundleAssociationKey: UInt8 = 0

private final class LocalizedBundleHelper {
    static func setCurrentLanguage(_ languageCode: String) {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            objc_setAssociatedObject(Bundle.main, &bundleAssociationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return
        }
        objc_setAssociatedObject(Bundle.main, &bundleAssociationKey, localizedBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        staticSwizzleOnce
    }
    
    private static let staticSwizzleOnce: Void = {
        let originalSelector = #selector(Bundle.localizedString(forKey:value:table:))
        let swizzledSelector = #selector(Bundle.customLocalizedString(forKey:value:table:))
        
        guard let originalMethod = class_getInstanceMethod(Bundle.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(Bundle.self, swizzledSelector) else {
            return
        }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()
}

private extension Bundle {
    @objc func customLocalizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let customBundle = objc_getAssociatedObject(self, &bundleAssociationKey) as? Bundle {
            return customBundle.customLocalizedString(forKey: key, value: value, table: tableName)
        }
        return self.customLocalizedString(forKey: key, value: value, table: tableName)
    }
}
