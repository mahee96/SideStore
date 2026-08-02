//
//  ImportedAccount.swift
//  AltStore
//
//  Created by ny on 9/7/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

struct ImportedAccount: Codable {
    let email: String
    let password: String?
    let certificateData: Data
    let certificatePassword: String
    let anisetteIdentifier: String
    let anisetteAdiBlob: String

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case certificateData
        case certificatePassword
        case anisetteIdentifier
        case anisetteAdiBlob

        // Legacy fallback keys
        case legacyCert = "cert"
        case legacyCertPass = "certpass"
        case legacyLocalUser = "local_user"
        case legacyAdiPB = "adiPB"
    }

    init(email: String, password: String?, certificateData: Data, certificatePassword: String, anisetteIdentifier: String, anisetteAdiBlob: String) {
        self.email = email
        self.password = password
        self.certificateData = certificateData
        self.certificatePassword = certificatePassword
        self.anisetteIdentifier = anisetteIdentifier
        self.anisetteAdiBlob = anisetteAdiBlob
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.email = try container.decode(String.self, forKey: .email)
        self.password = try container.decodeIfPresent(String.self, forKey: .password)

        if let certData = try container.decodeIfPresent(Data.self, forKey: .certificateData) {
            self.certificateData = certData
        } else {
            self.certificateData = try container.decode(Data.self, forKey: .legacyCert)
        }

        if let certPass = try container.decodeIfPresent(String.self, forKey: .certificatePassword) {
            self.certificatePassword = certPass
        } else {
            self.certificatePassword = try container.decode(String.self, forKey: .legacyCertPass)
        }

        if let identifier = try container.decodeIfPresent(String.self, forKey: .anisetteIdentifier) {
            self.anisetteIdentifier = identifier
        } else {
            self.anisetteIdentifier = try container.decode(String.self, forKey: .legacyLocalUser)
        }

        if let adiBlob = try container.decodeIfPresent(String.self, forKey: .anisetteAdiBlob) {
            self.anisetteAdiBlob = adiBlob
        } else {
            self.anisetteAdiBlob = try container.decode(String.self, forKey: .legacyAdiPB)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(password, forKey: .password)
        try container.encode(certificateData, forKey: .certificateData)
        try container.encode(certificatePassword, forKey: .certificatePassword)
        try container.encode(anisetteIdentifier, forKey: .anisetteIdentifier)
        try container.encode(anisetteAdiBlob, forKey: .anisetteAdiBlob)
    }
}
