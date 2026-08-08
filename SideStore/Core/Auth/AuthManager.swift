//
//  AuthManager.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltSign
@preconcurrency import AltStoreCore

public final class AuthManager: @unchecked Sendable {
    public static let shared = AuthManager()
    
    private init() {}
    
    public var isAuthenticated: Bool {
        let hasEmail = Keychain.shared.appleIDEmailAddress != nil
        let hasPassword = Keychain.shared.appleIDPassword != nil
        let hasToken = Keychain.shared.appleIDXcodeToken != nil
        return hasEmail && (hasPassword || hasToken)
    }
    
    public var currentAppleID: String? {
        get { Keychain.shared.appleIDEmailAddress }
        set { Keychain.shared.appleIDEmailAddress = newValue }
    }
    
    public var password: String? {
        get { Keychain.shared.appleIDPassword }
        set { Keychain.shared.appleIDPassword = newValue }
    }
    
    public var team: ALTTeam? {
        get { Keychain.shared.team }
        set { Keychain.shared.team = newValue }
    }
    
    public var session: ALTAppleAPISession? {
        get { Keychain.shared.session }
        set { Keychain.shared.session = newValue }
    }
    
    public var adsid: String? {
        get { Keychain.shared.appleIDAdsid }
        set { Keychain.shared.appleIDAdsid = newValue }
    }
    
    public var xcodeToken: String? {
        get { Keychain.shared.appleIDXcodeToken }
        set { Keychain.shared.appleIDXcodeToken = newValue }
    }
    
    public var hasStoredPassword: Bool {
        return Keychain.shared.appleIDPassword != nil
    }
    
    public var hasStoredXcodeToken: Bool {
        return Keychain.shared.appleIDXcodeToken != nil
    }
    
    public func clearSession() {
        Keychain.shared.team = nil
        Keychain.shared.session = nil
        CertificateManager.shared.clearActiveCertificate()
    }
    
    public func signOut() {
        Keychain.shared.appleIDEmailAddress = nil
        Keychain.shared.appleIDPassword = nil
        Keychain.shared.appleIDXcodeToken = nil
        Keychain.shared.appleIDAdsid = nil
        clearSession()
    }
    
    // MARK: - Developer Portal API Operations
    
    public func authenticate(presentingViewController: UIViewController?) async throws -> (ALTTeam, ALTAppleAPISession) {
        return try await DeveloperPortalService.shared.authenticate(presentingViewController: presentingViewController)
    }
    
    public func fetchCertificates(team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTCertificate] {
        return try await DeveloperPortalService.shared.fetchCertificates(team: team, session: session)
    }
    
    public func createCertificate(machineName: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
        return try await DeveloperPortalService.shared.createCertificate(machineName: machineName, team: team, session: session)
    }
    
    public func revokeCertificate(_ certificate: ALTCertificate, team: ALTTeam, session: ALTAppleAPISession) async throws -> Bool {
        return try await DeveloperPortalService.shared.revokeCertificate(certificate, team: team, session: session)
    }
    
    @discardableResult
    func performAuthenticationOperation(
        context: AuthenticatedOperationContext,
        details: AuthenticationDetails,
        skipDeviceRegistration: Bool = false,
        skipCertificateProvisioning: Bool = false
    ) async throws -> AuthenticationResult {
        let authOperation = try AuthenticationOperation(
            context: context,
            details: details,
            skipDeviceRegistration: skipDeviceRegistration,
            skipCertificateProvisioning: skipCertificateProvisioning
        )
        return try await authOperation.execute()
    }
}
