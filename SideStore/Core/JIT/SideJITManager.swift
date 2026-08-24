//
//  SideJITManager.swift
//  SideStore
//
//  Created by Magesh K on 14/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

public final class SideJITManager {
    public static let shared = SideJITManager()
    
    private init() {}
    
    public func resolveServerURL() async -> String {
        if let userInput = UserDefaults.standard.textInputSideJITServerurl, !userInput.isEmpty {
            if let resolved = await resolveAddressIfNeeded(userInput) {
                return resolved
            }
            return userInput
        }
        
        if let resolved = await BonjourDiscoveryManager.resolveFirstService(
            ofType: AppConstants.SideJIT.bonjourServiceType,
            namePrefix: AppConstants.SideJIT.bonjourServiceName,
            timeout: AppConstants.SideJIT.timeout
        ) {
            let cleanHost = resolved.host.strippingInterfaceScope
            let url = "http://\(cleanHost):\(resolved.port)"
            debugLog("[SideJITManager] Discovered SideJITServer via Bonjour at: \(url)")
            return url
        }
        
        if let fallback = await resolveAddressIfNeeded(AppConstants.SideJIT.defaultServerURL) {
            return fallback
        }
        
        return AppConstants.SideJIT.defaultServerURL
    }
    
    private func resolveAddressIfNeeded(_ input: String) async -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let urlString = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        let port = url.port ?? 8080
        
        // 1. Direct IP address
        if host.filter({ $0 == "." }).count == 3 || host.contains(":") {
            return "http://\(host):\(port)"
        }
        
        // 2. DNS-SD Bonjour Service Descriptor (e.g. sidejitserver._http._tcp.local or _http._tcp)
        if host.contains("._tcp") || host.contains("._udp") {
            let parts = host.components(separatedBy: "._")
            let namePrefix = parts.first ?? ""
            let serviceType = parts.count > 1 ? "_\(parts.dropFirst().joined(separator: "._"))" : AppConstants.SideJIT.bonjourServiceType
            let cleanType = serviceType.replacingOccurrences(of: ".local", with: "")
            
            if let resolved = await BonjourDiscoveryManager.resolveFirstService(
                ofType: cleanType.isEmpty ? AppConstants.SideJIT.bonjourServiceType : cleanType,
                namePrefix: namePrefix == cleanType ? "" : namePrefix,
                timeout: AppConstants.SideJIT.timeout
            ) {
                let cleanHost = resolved.host.strippingInterfaceScope
                let resolvedPort = resolved.port > 0 ? resolved.port : UInt16(port)
                let resolvedURL = "http://\(cleanHost):\(resolvedPort)"
                debugLog("[SideJITManager] Resolved mDNS service '\(host)' via Bonjour to: \(resolvedURL)")
                return resolvedURL
            }
        }
        
        // 3. Local hostname (.local)
        if host.hasSuffix(".local") {
            let ips = BonjourDiscoveryManager.resolveHostToIPs(host)
            if let firstIP = ips.first {
                let resolvedURL = "http://\(firstIP):\(port)"
                debugLog("[SideJITManager] Resolved host '\(host)' to IP: \(resolvedURL)")
                return resolvedURL
            }
        }
        
        return "http://\(host):\(port)"
    }
    
    public func askForNetwork() async {
        let SJSURL = await resolveServerURL()
        guard let url = URL(string: "\(SJSURL)/re/") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = AppConstants.SideJIT.timeout
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                    debugLog("[SideJITManager] askForNetwork: received response from \(url) (status: \(status))")
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(AppConstants.SideJIT.timeout * 1_000_000_000))
                    throw URLError(.timedOut)
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            debugLog("[SideJITManager] askForNetwork error: \(error)")
        }
    }

    public func isSideJITServerDetected() async throws {
        let SJSURL = await resolveServerURL()
        guard let url = URL(string: SJSURL) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = AppConstants.SideJIT.timeout
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                debugLog("[SideJITManager] SideJITServer detected at \(url) (status: \(status))")
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(AppConstants.SideJIT.timeout * 1_000_000_000))
                throw URLError(.timedOut)
            }
            try await group.next()
            group.cancelAll()
        }
    }
}

// MARK: - UI Extension
extension SideJITManager {
    @MainActor
    public func presentJITPrompt(presentingVC: UIViewController) {
        let alert = UIAlertController(
            title: "SideJITServer Detected",
            message: "Would you like to enable SideJITServer",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in UserDefaults.standard.isSideJITServerEnabled = true })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentingVC.present(alert, animated: true)
    }
}
