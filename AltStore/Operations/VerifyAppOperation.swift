//
//  VerifyAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CryptoKit

import AltStoreCore
import AltSign
import Roxas

extension VerificationError
{
    enum Code: Int, ALTErrorCode, CaseIterable {
        typealias Error = VerificationError

        case privateEntitlements
        case mismatchedBundleIdentifiers
        case iOSVersionNotSupported
    }

    static func privateEntitlements(_ entitlements: [String: Any], app: ALTApplication) -> VerificationError {
        VerificationError(code: .privateEntitlements, app: app, entitlements: entitlements)
    }

    static func mismatchedBundleIdentifiers(sourceBundleID: String, app: ALTApplication) -> VerificationError {
        VerificationError(code: .mismatchedBundleIdentifiers, app: app, sourceBundleID: sourceBundleID)
    }

    static func iOSVersionNotSupported(app: AppProtocol, osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion, requiredOSVersion: OperatingSystemVersion?) -> VerificationError {
        VerificationError(code: .iOSVersionNotSupported, app: app)
    }
}

struct VerificationError: ALTLocalizedError {
    let code: Code

    var errorTitle: String?
    var errorFailure: String?
    @Managed var app: AppProtocol?
    var sourceBundleID: String?
    var deviceOSVersion: OperatingSystemVersion?
    var requiredOSVersion: OperatingSystemVersion?
    
    var errorDescription: String? {
        switch self.code {
        case .iOSVersionNotSupported:
            guard let deviceOSVersion else { return nil }

            var failureReason = self.errorFailureReason
            if self.app == nil {
                let firstLetter = failureReason.prefix(1).lowercased()
                failureReason = firstLetter + failureReason.dropFirst()
            }

            return String(formatted: "This device is running iOS %@, but %@", deviceOSVersion.stringValue, failureReason)
        default: return nil
        }
        
        return self.errorFailureReason
    }

    var errorFailureReason: String {
        switch self.code
        {
        case .privateEntitlements:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            return String(formatted: "“%@” requires private permissions.", appName)

        case .mismatchedBundleIdentifiers:
            if let appBundleID = self.$app.bundleIdentifier, let bundleID = self.sourceBundleID {
                return String(formatted: "The bundle ID '%@' does not match the one specified by the source ('%@').", appBundleID, bundleID)
            } else {
                return NSLocalizedString("The bundle ID does not match the one specified by the source.", comment: "")
            }

        case .iOSVersionNotSupported:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            let deviceOSVersion = self.deviceOSVersion ?? ProcessInfo.processInfo.operatingSystemVersion

            guard let requiredOSVersion else {
                return String(formatted: "%@ does not support iOS %@.", appName, deviceOSVersion.stringValue)
            }
            if deviceOSVersion > requiredOSVersion {
                return String(formatted: "%@ requires iOS %@ or earlier", appName, requiredOSVersion.stringValue)
            } else {
                return String(formatted: "%@ requires iOS %@ or later", appName, requiredOSVersion.stringValue)
            }
        }
    }
}

@objc(VerifyAppOperation)
final class VerifyAppOperation: ResultOperation<Void>
{
    let context: InstallAppOperationContext
    var verificationHandler: ((VerificationError) -> Bool)?
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        do
        {
            if let error = self.context.error
            {
                throw error
            }
            let appName = self.context.app?.name ?? NSLocalizedString("The app", comment: "")
            self.localizedFailure = String(format: NSLocalizedString("%@ could not be installed.", comment: ""), appName)
            
            guard let app = self.context.app else {
                throw OperationError.invalidParameters("VerifyAppOperation.main: self.context.app is nil")
            }
            
            if !["ny.litritt.ignited", "com.litritt.ignited"].contains(where: { $0 == app.bundleIdentifier }) {
                guard app.bundleIdentifier == self.context.bundleIdentifier else {
                    throw VerificationError.mismatchedBundleIdentifiers(sourceBundleID: self.context.bundleIdentifier, app: app)
                }
            }
            
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(app.minimumiOSVersion) else {
                throw VerificationError.iOSVersionNotSupported(app: app, requiredOSVersion: app.minimumiOSVersion)
            }
            
            guard let appVersion = self.context.appVersion else {
                return self.finish(.success(()))
            }
            
            Task<Void, Never>  {
                do
                {
                    guard let ipaURL = self.context.ipaURL else { throw OperationError.appNotFound(name: app.name) }
                    
                    try await self.verifyHash(of: app, at: ipaURL, matches: appVersion)
                    try await self.verifyDownloadedVersion(of: app, matches: appVersion)
                    
                    self.finish(.success(()))
                }
                catch
                {
                    self.finish(.failure(error))
                }
            }
        }
        catch
        {
            self.finish(.failure(error))
        }
    }
}

private extension VerifyAppOperation
{
    func verifyHash(of app: ALTApplication, at ipaURL: URL, @AsyncManaged matches appVersion: AppVersion) async throws
    {
        // Do nothing if source doesn't provide hash.
        guard let expectedHash = await $appVersion.sha256 else { return }

        let data = try Data(contentsOf: ipaURL)
        let sha256Hash = SHA256.hash(data: data)
        let hashString = sha256Hash.compactMap { String(format: "%02x", $0) }.joined()

        print("[ALTLog] Comparing app hash (\(hashString)) against expected hash (\(expectedHash))...")

        guard hashString == expectedHash else { throw VerificationError.mismatchedHash(hashString, expectedHash: expectedHash, app: app) }
    }
    
    func verifyDownloadedVersion(of app: ALTApplication, @AsyncManaged matches appVersion: AppVersion) async throws
    {
        let version = await $appVersion.version
        
        guard version == app.version else { throw VerificationError.mismatchedVersion(app.version, expectedVersion: version, app: app) }
    }
}
