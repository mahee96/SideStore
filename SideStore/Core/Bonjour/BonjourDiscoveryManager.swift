//
//  BonjourDiscoveryManager.swift
//  SideStore
//
//  Created by Magesh K on 4/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Network
import Combine

struct ServiceTypeInfo: Identifiable, Hashable {
    var id: String { rawType }
    let rawType: String
    let friendlyName: String?
    
    var displayName: String {
        friendlyName ?? rawType
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawType)
    }
    
    static func == (lhs: ServiceTypeInfo, rhs: ServiceTypeInfo) -> Bool {
        lhs.rawType == rhs.rawType
    }
}

struct DiscoveredService: Identifiable, Hashable {
    var id: String { "\(domain)/\(type)/\(name)" }
    let name: String
    let type: String
    let domain: String
    let result: NWBrowser.Result
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DiscoveredService, rhs: DiscoveredService) -> Bool {
        lhs.id == rhs.id
    }
}

struct ResolvedServiceInfo: Identifiable {
    var id: String { "\(domain)/\(type)/\(name)/\(hostname):\(port)" }
    let name: String
    let type: String
    let domain: String
    let hostname: String
    let port: UInt16
    let addresses: [String]
    let txtRecords: [(key: String, value: String)]
}

final class BonjourDiscoveryManager: NSObject, ObservableObject, NetServiceDelegate, NetServiceBrowserDelegate {
    static let shared = BonjourDiscoveryManager()
    
    // Published State
    @Published var domains: [String] = []
    @Published var serviceTypes: [ServiceTypeInfo] = []
    @Published var instances: [DiscoveredService] = []
    @Published var resolvedService: ResolvedServiceInfo? = nil
    @Published var isSearching = false
    @Published var resolveError: String? = nil
    
    // Private State
    private var domainBrowser: NetServiceBrowser?
    private var typeBrowser: NetServiceBrowser?
    private var fallbackTypeBrowsers: [NWBrowser] = []
    private var instanceBrowsers: [NWBrowser] = []
    private var activeConnection: NWConnection?
    private var resolvingNetService: NetService?
    private var activeTxtRecords: [(key: String, value: String)] = []
    private var currentResolvingService: DiscoveredService?
    private var timeoutTask: Task<Void, Never>?
    
    private var discoveredDomains = Set<String>()
    private var discoveredTypes = Set<String>()
    private var discoveredInstances = Set<DiscoveredService>()
    
    override init() {
        super.init()
    }
    
    // Domain Discovery
    func discoverDomains(clearExisting: Bool = false) {
        debugLog("[BonjourDiscovery] Starting domain discovery...")
        stopDomainSearch()
        if clearExisting {
            discoveredDomains.removeAll()
            domains.removeAll()
        }
        isSearching = true
        
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForRegistrationDomains()
        domainBrowser = browser
        
        if !domains.contains("local") {
            domains.append("local")
            discoveredDomains.insert("local")
        }
    }
    
    func stopDomainSearch() {
        domainBrowser?.stop()
        domainBrowser = nil
        isSearching = false
    }
    
    // Service Type Discovery
    func discoverServiceTypes(in domain: String = "local.", probeTypes: [String]? = nil, clearExisting: Bool = false) {
        let domainWithDot = domain.hasSuffix(".") ? domain : domain + "."
        debugLog("[BonjourDiscovery] Starting service type discovery in domain '\(domainWithDot)'...")
        stopTypeSearch()
        if clearExisting {
            discoveredTypes.removeAll()
            serviceTypes.removeAll()
        }
        isSearching = true
        
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_services._dns-sd._udp.", inDomain: domainWithDot)
        typeBrowser = browser
        
        let typesToProbe = probeTypes ?? commonServiceTypesToBrowse
        if !typesToProbe.isEmpty {
            startFallbackSearches(types: typesToProbe, in: domainWithDot)
        }
        
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            self.isSearching = false
        }
    }
    
    private func startFallbackSearches(types: [String], in domain: String) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            for t in types {
                let typeWithoutDot = t.hasSuffix(".") ? String(t.dropLast()) : t
                let parameters = typeWithoutDot.contains("_tcp") ? NWParameters.tcp : NWParameters.udp
                parameters.includePeerToPeer = true
                
                let descriptor = NWBrowser.Descriptor.bonjour(type: typeWithoutDot, domain: domain)
                let browser = NWBrowser(for: descriptor, using: parameters)
                
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    guard let self = self else { return }
                    if !results.isEmpty {
                        Task { @MainActor in
                            if self.discoveredTypes.insert(t).inserted {
                                let info = ServiceTypeInfo(
                                    rawType: t,
                                    friendlyName: Self.friendlyName(for: t)
                                )
                                if !self.serviceTypes.contains(where: { $0.rawType == t }) {
                                    self.serviceTypes.append(info)
                                    self.serviceTypes.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                                }
                            }
                        }
                    }
                }
                
                browser.start(queue: .global(qos: .userInitiated))
                
                Task { @MainActor in
                    self.fallbackTypeBrowsers.append(browser)
                }
            }
        }
    }
    
    func stopTypeSearch() {
        typeBrowser?.stop()
        typeBrowser = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        for b in fallbackTypeBrowsers {
            b.cancel()
        }
        fallbackTypeBrowsers.removeAll()
        isSearching = false
    }
    
    // Service Instance Discovery
    func discoverInstances(ofType type: String, inDomain domain: String = "local.", clearExisting: Bool = false) {
        discoverInstances(ofTypes: [type], inDomain: domain, clearExisting: clearExisting)
    }
    
    func discoverInstances(ofTypes types: [String], inDomain domain: String = "local.", clearExisting: Bool = false) {
        let domainWithDot = domain.hasSuffix(".") ? domain : domain + "."
        debugLog("[BonjourDiscovery] Starting instance discovery for types: \(types) in '\(domainWithDot)'...")
        stopInstanceSearch()
        if clearExisting {
            discoveredInstances.removeAll()
            instances.removeAll()
        }
        isSearching = true
        
        for type in types {
            let typeWithoutDot = type.hasSuffix(".") ? String(type.dropLast()) : type
            let descriptor = NWBrowser.Descriptor.bonjour(type: typeWithoutDot, domain: domainWithDot)
            let parameters = typeWithoutDot.contains("_tcp") ? NWParameters.tcp : NWParameters.udp
            parameters.includePeerToPeer = true
            
            let browser = NWBrowser(for: descriptor, using: parameters)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.handleInstanceResults(results, forType: type, domain: domain)
            }
            
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    Task { @MainActor in
                        self?.isSearching = false
                    }
                }
            }
            
            instanceBrowsers.append(browser)
            browser.start(queue: .global(qos: .userInitiated))
        }
        
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            self.isSearching = false
        }
    }
    
    private func handleInstanceResults(_ results: Set<NWBrowser.Result>, forType type: String, domain: String) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Build incoming map
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint {
                    let discovered = DiscoveredService(
                        name: name,
                        type: type,
                        domain: domain,
                        result: result
                    )
                    if let existingIndex = self.instances.firstIndex(where: { $0.id == discovered.id }) {
                        self.instances[existingIndex] = discovered
                    } else {
                        self.instances.append(discovered)
                    }
                }
            }
            self.instances.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.isSearching = false
        }
    }
    
    func stopInstanceSearch() {
        debugLog("[BonjourDiscovery] Stopping instance discovery.")
        timeoutTask?.cancel()
        timeoutTask = nil
        for b in instanceBrowsers {
            b.cancel()
        }
        instanceBrowsers.removeAll()
        isSearching = false
    }
    
    // Service Resolution
    func resolveService(_ service: DiscoveredService) {
        debugLog("[BonjourDiscovery] Resolving service '\(service.name)'...")
        stopResolving()
        
        resolvedService = nil
        resolveError = nil
        isSearching = true
        currentResolvingService = service
        
        var txtRecords: [(key: String, value: String)] = []
        if case .bonjour(let txtRecord) = service.result.metadata {
            let dict = txtRecord.dictionary
            for (key, value) in dict {
                txtRecords.append((key: key, value: value))
            }
            txtRecords.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        }
        activeTxtRecords = txtRecords
        
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        
        let connection = NWConnection(to: service.result.endpoint, using: parameters)
        activeConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready, .waiting:
                if let path = connection.currentPath,
                   let remote = path.remoteEndpoint,
                   case .hostPort(let host, let port) = remote {
                    
                    var resolvedHost = "\(host)"
                    if let percentIndex = resolvedHost.firstIndex(of: "%") {
                        resolvedHost = String(resolvedHost[..<percentIndex])
                    }
                    let portVal = port.rawValue
                    
                    self.finishResolution(
                        service: service,
                        hostname: resolvedHost,
                        port: portVal,
                        txtRecords: txtRecords
                    )
                }
            case .failed(let error):
                debugLog("[BonjourDiscovery] NWConnection resolution failed: \(error)")
            default:
                break
            }
        }
        connection.start(queue: .main)
        
        let netType = service.type.hasSuffix(".") ? service.type : service.type + "."
        let netDomain = service.domain.isEmpty ? "local." : (service.domain.hasSuffix(".") ? service.domain : service.domain + ".")
        let ns = NetService(domain: netDomain, type: netType, name: service.name)
        ns.delegate = self
        resolvingNetService = ns
        ns.resolve(withTimeout: 4.0)
        
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            if self.isSearching && self.resolvedService == nil {
                self.stopResolving()
                self.resolveError = "Resolution timed out (no response from endpoint)"
            }
        }
    }
    
    private func finishResolution(
        service: DiscoveredService,
        hostname: String,
        port: UInt16,
        txtRecords: [(key: String, value: String)]
    ) {
        Task { @MainActor [weak self] in
            guard let self = self, self.isSearching, self.resolvedService == nil else { return }
            
            self.stopResolving()
            let addresses = Self.resolveHostToIPs(hostname)
            
            self.resolvedService = ResolvedServiceInfo(
                name: service.name,
                type: service.type,
                domain: service.domain,
                hostname: hostname,
                port: port,
                addresses: addresses,
                txtRecords: txtRecords
            )
            self.isSearching = false
        }
    }
    
    func stopResolving() {
        timeoutTask?.cancel()
        timeoutTask = nil
        activeConnection?.cancel()
        activeConnection = nil
        resolvingNetService?.stop()
        resolvingNetService = nil
        currentResolvingService = nil
        isSearching = false
    }
    
    func stopAll() {
        stopDomainSearch()
        stopTypeSearch()
        stopInstanceSearch()
        stopResolving()
    }
    
    // NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFindDomain domainString: String, moreComing: Bool) {
        let cleanDomain = domainString.hasSuffix(".") ? String(domainString.dropLast()) : domainString
        Task { @MainActor in
            if self.discoveredDomains.insert(cleanDomain).inserted {
                self.domains.append(cleanDomain)
            }
            if !moreComing {
                self.isSearching = false
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let rawType = "\(service.name).\(service.type)"
        Task { @MainActor in
            if self.discoveredTypes.insert(rawType).inserted {
                let info = ServiceTypeInfo(
                    rawType: rawType,
                    friendlyName: Self.friendlyName(for: rawType)
                )
                self.serviceTypes.append(info)
                self.serviceTypes.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
            if !moreComing {
                self.isSearching = false
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
    
    // NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        let hostname = sender.hostName ?? ""
        let port = UInt16(sender.port)
        
        var cleanHost = hostname
        if cleanHost.hasSuffix(".") {
            cleanHost = String(cleanHost.dropLast())
        }
        
        var txtRecords: [(key: String, value: String)] = []
        if let txtData = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            for (k, v) in dict {
                let valStr = String(data: v, encoding: .utf8) ?? ""
                txtRecords.append((key: k, value: valStr))
            }
        }
        
        Task { @MainActor in
            guard let service = self.currentResolvingService else { return }
            let finalRecords = self.activeTxtRecords.isEmpty ? txtRecords : self.activeTxtRecords
            self.finishResolution(
                service: service,
                hostname: cleanHost.isEmpty ? service.name : cleanHost,
                port: port,
                txtRecords: finalRecords
            )
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        debugLog("[BonjourDiscovery] NetService failed to resolve: \(errorDict)")
    }
    
    // Helpers
    static func friendlyName(for rawType: String) -> String? {
        let normalized = rawType.hasSuffix(".") ? rawType : rawType + "."
        return commonKnownServiceTypes[normalized]
    }
    
    static func resolveHostToIPs(_ host: String) -> [String] {
        var addresses: [String] = []
        var results: UnsafeMutablePointer<addrinfo>?
        
        let rc = getaddrinfo(host, nil, nil, &results)
        if rc == 0, let firstAddr = results {
            var ptr: UnsafeMutablePointer<addrinfo>? = firstAddr
            while ptr != nil {
                if let addr = ptr?.pointee {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let saLen = socklen_t(addr.ai_addrlen)
                    let nameInfoResult = getnameinfo(
                        addr.ai_addr,
                        saLen,
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if nameInfoResult == 0 {
                        let ipStr = String(cString: hostname)
                        if !ipStr.isEmpty && !addresses.contains(ipStr) {
                            addresses.append(ipStr)
                        }
                    }
                }
                ptr = ptr?.pointee.ai_next
            }
            freeaddrinfo(results)
        }
        return addresses
    }
    
    private final class OneShotResolver: @unchecked Sendable {
        private let lock = NSLock()
        private var isResumed = false
        private var browser: NWBrowser?
        private var activeConnection: NWConnection?
        private var continuation: CheckedContinuation<(host: String, port: UInt16)?, Never>?
        
        init(continuation: CheckedContinuation<(host: String, port: UInt16)?, Never>) {
            self.continuation = continuation
        }
        
        func setBrowser(_ browser: NWBrowser) {
            lock.lock()
            self.browser = browser
            lock.unlock()
        }
        
        func setActiveConnection(_ connection: NWConnection) {
            lock.lock()
            self.activeConnection = connection
            lock.unlock()
        }
        
        func resumeOnce(_ result: (host: String, port: UInt16)?) {
            lock.lock()
            guard !isResumed else {
                lock.unlock()
                return
            }
            isResumed = true
            let continuation = self.continuation
            self.continuation = nil
            let browser = self.browser
            self.browser = nil
            let connection = self.activeConnection
            self.activeConnection = nil
            lock.unlock()
            
            browser?.cancel()
            connection?.cancel()
            continuation?.resume(returning: result)
        }
    }
    
    static func resolveFirstService(
        ofType rawType: String,
        namePrefix: String = "",
        timeout: TimeInterval = AppConstants.Bonjour.defaultDiscoveryTimeout
    ) async -> (host: String, port: UInt16)? {
        let typeWithoutDot = rawType.hasSuffix(".") ? String(rawType.dropLast()) : rawType
        let descriptor = NWBrowser.Descriptor.bonjour(type: typeWithoutDot, domain: AppConstants.Bonjour.defaultDomain)
        let parameters = typeWithoutDot.contains("_tcp") ? NWParameters.tcp : NWParameters.udp
        parameters.includePeerToPeer = true
        
        let browser = NWBrowser(for: descriptor, using: parameters)
        
        return await withCheckedContinuation { continuation in
            let resolver = OneShotResolver(continuation: continuation)
            resolver.setBrowser(browser)
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                resolver.resumeOnce(nil)
            }
            
            browser.browseResultsChangedHandler = { results, _ in
                guard let target = results.first(where: {
                    guard case .service(let name, _, _, _) = $0.endpoint else { return false }
                    return namePrefix.isEmpty || name.localizedCaseInsensitiveContains(namePrefix)
                }), case .service(let name, _, _, _) = target.endpoint else { return }
                
                let conn = NWConnection(to: target.endpoint, using: parameters)
                resolver.setActiveConnection(conn)
                
                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready, .waiting:
                        guard let remote = conn.currentPath?.remoteEndpoint,
                              case .hostPort(let host, let port) = remote else { return }
                        
                        let hostStr = "\(host)"
                        let ips = resolveHostToIPs(hostStr)
                        let finalHost = ips.first ?? hostStr
                        debugLog("[BonjourDiscovery] Auto-resolved '\(name)' to \(finalHost):\(port.rawValue)")
                        resolver.resumeOnce((host: finalHost, port: port.rawValue))
                        
                    case .failed:
                        resolver.resumeOnce(nil)
                        
                    default:
                        break
                    }
                }
                
                conn.start(queue: .global(qos: .userInitiated))
            }
            
            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    resolver.resumeOnce(nil)
                }
            }
            
            browser.start(queue: .global(qos: .userInitiated))
        }
    }
}
