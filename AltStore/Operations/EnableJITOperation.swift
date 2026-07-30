//
//  EnableJITOperation.swift
//  EnableJITOperation
//
//  Created by Riley Testut on 9/1/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import Combine
import UniformTypeIdentifiers
@preconcurrency import AltStoreCore

enum SideJITServerErrorType: Error {
     case invalidURL
     case errorConnecting
     case deviceNotFound
     case other(String)
 }

@available(iOS 14, *)
final class EnableJITOperation: AsyncOperation<InstallAppOperationContext, Bool>, @unchecked Sendable
{
    private var cancellable: AnyCancellable?
    
    override func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> Bool {
        try await super.execute(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: weights)
        
        guard let installedApp = self.context.installedApp else {
            throw OperationError.invalidParameters("EnableJITOperation.main: self.context.installedApp is nil")
        }
        
        try await self.enableJIT(for: installedApp)
        return true
    }

    private func enableJIT(for installedApp: InstalledApp) async throws
    {
        let userdefaults = UserDefaults.standard
        
        if #available(iOS 17, *), userdefaults.sidejitenable {
            let sideJITIP = userdefaults.textInputSideJITServerurl ?? "http://sidejitserver._http._tcp.local:8080"
            guard let serverURL = URL(string: sideJITIP) else {
                throw OperationError.unableToConnectSideJIT
            }
            do {
                try await enableJITSideJITServer(serverURL: serverURL, installedApp: installedApp)
                self.debugLog("JIT Enabled Successfully :3 (code made by Stossy11!)")
            } catch {
                if let serverError = error as? SideJITServerErrorType {
                    switch serverError {
                    case .invalidURL, .errorConnecting:
                        throw OperationError.unableToConnectSideJIT
                    case .deviceNotFound:
                        throw OperationError.unableToRespondSideJITDevice
                    case .other(let message):
                        if let startRange = message.range(of: "<p>"),
                           let endRange = message.range(of: "</p>", range: startRange.upperBound..<message.endIndex) {
                            let pContent = message[startRange.upperBound..<endRange.lowerBound]
                            self.debugLog(message + " + " + String(pContent))
                            throw OperationError.SideJITIssue(error: String(pContent))
                        } else {
                            self.debugLog(message)
                            throw OperationError.SideJITIssue(error: message)
                        }
                    }
                } else {
                    throw error
                }
            }
        } else {
            guard let ctx = installedApp.managedObjectContext else {
                throw OperationError.invalidParameters("EnableJITOperation: installedApp.managedObjectContext is nil")
            }
            let targetBundleId = await ctx.perform { installedApp.resignedBundleIdentifier }

            var lastError: Error?
            let maxRetries = 3
            for _ in 0..<maxRetries {
                do {
                    try await debugApp(targetBundleId)
                    return
                } catch {
                    lastError = error
                }
            }
            if let error = lastError { throw error }
        }
    }
}

@available(iOS 17, *)
func enableJITSideJITServer(serverURL: URL, installedApp: InstalledApp) async throws {
    guard let udid = try await fetchUDID() else {
        throw SideJITServerErrorType.other("Unable to get UDID")
    }
    
    let serverURLWithUDID = serverURL.appendingPathComponent(udid)
    let fullURL = serverURLWithUDID.appendingPathComponent(installedApp.resignedBundleIdentifier)
    
    let (data, _) = try await URLSession.shared.data(from: fullURL)
    
    guard let dataString = String(data: data, encoding: .utf8) else {
        throw SideJITServerErrorType.other("Invalid response data")
    }
    
    if dataString == "Enabled JIT for '\(installedApp.name)'!" {
        let content = UNMutableNotificationContent()
        content.title = "JIT Successfully Enabled"
        content.subtitle = "JIT Enabled For \(installedApp.name)"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "EnabledJIT", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    } else {
        let errorType: SideJITServerErrorType = dataString == "Could not find device!"
            ? .deviceNotFound
            : .other(dataString)
        throw errorType
    }
}
