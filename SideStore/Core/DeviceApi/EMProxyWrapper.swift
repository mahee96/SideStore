//
//  EMProxyWrapper.swift
//  SideStore
//
//  Created by Magesh K on 22/02/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Minimuxer

func startEMProxy(bind_addr: String = AppConstants.Proxy.serverURL) async throws {
    debugLog("[SideStore] startEMProxy(\(bind_addr)) invoked")
    defer { debugLog("[SideStore] startEMProxy() completed") }

    #if targetEnvironment(simulator)
    debugLog("[SideStore] startEMProxy() is no-op on simulator")
    #else
    let components = bind_addr.split(separator: ":")
    guard components.count >= 1 && components.count <= 2 else {
        debugLog("[SideStore] startEMProxy() invalid bind_addr format: \(bind_addr)")
        throw EMProxyError.invalidSocketAddress(bind_addr)
    }

    let defaultAddress = AppConstants.Proxy.address
    let defaultPort = AppConstants.Proxy.defaultPort

    let host = components.first.map(String.init) ?? defaultAddress
    let port = components.count == 2 ? (components.last.flatMap { UInt16($0) } ?? defaultPort) : defaultPort
    do {
        try await Minimuxer.emproxy.start(host: host, port: port)
    } catch {
        debugLog("[SideStore] startEMProxy() failed with error: \(error)")
        throw error
    }
    #endif
}

func stopEMProxy() async throws {
    debugLog("[SideStore] stopEMProxy() invoked")
    defer { debugLog("[SideStore] stopEMProxy() completed") }

    #if targetEnvironment(simulator)
    debugLog("[SideStore] stopEMProxy() is no-op on simulator")
    #else
    do {
        try await Minimuxer.emproxy.stop()
    } catch {
        debugLog("[SideStore] stopEMProxy() failed with error: \(error)")
        throw error
    }
    #endif
}
