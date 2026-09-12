//
//  CertificateTypes.swift
//  SideStore
//
//  Created by Magesh K on 2026-07-03.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SideSign

enum SortOption: String, CaseIterable, Identifiable {
    case creationDate = "Creation Date"
    case expiryDate   = "Expiry Date"
    case name         = "Name"
    case keys         = "Keys"
    case type         = "Type"
    var id: String { rawValue }
    var localizedName: String {
        switch self {
        case .creationDate: return localized("Creation Date")
        case .expiryDate:   return localized("Expiry Date")
        case .name:         return localized("Name")
        case .keys:         return localized("Keys")
        case .type:         return localized("Type")
        }
    }
}

enum GroupOption: String, CaseIterable, Identifiable {
    case none         = "None"
    case creationDate = "Creation Date"
    case expiryDate   = "Expiry Date"
    case name         = "Name"
    case keys         = "Keys"
    case type         = "Type"
    var id: String { rawValue }
    var localizedName: String {
        switch self {
        case .none:         return localized("None")
        case .creationDate: return localized("Creation Date")
        case .expiryDate:   return localized("Expiry Date")
        case .name:         return localized("Name")
        case .keys:         return localized("Keys")
        case .type:         return localized("Type")
        }
    }
}

enum FileImportMode {
    case certificate
    case privateKey
}

struct KeyTextImportItem: Identifiable {
    let id: String
    let cert: ALTX509Certificate
}

struct GroupedCertificates: Identifiable {
    var id: String { name }
    let name: String
    let certificates: [ALTX509Certificate]
}
