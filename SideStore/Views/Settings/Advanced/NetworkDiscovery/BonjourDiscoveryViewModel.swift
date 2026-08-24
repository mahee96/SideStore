//
//  BonjourDiscoveryViewModel.swift
//  SideStore
//
//  Created by Magesh K on 24/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

enum ServiceTypeSortOption: String, CaseIterable {
    case nameAscending = "Name (A to Z)"
    case nameDescending = "Name (Z to A)"
    case rawType = "Raw Type Identifier"
}

enum ServiceTypeGroupOption: String, CaseIterable {
    case none = "None"
    case protocolType = "Protocol (TCP / UDP)"
    case category = "Category (Recognized / Other)"
    case firstLetter = "First Letter"
}

enum ServiceInstanceSortOption: String, CaseIterable {
    case nameAscending = "Name (A to Z)"
    case nameDescending = "Name (Z to A)"
}

enum ServiceInstanceGroupOption: String, CaseIterable {
    case none = "None"
    case firstLetter = "First Letter"
}

struct DomainSection: Identifiable {
    let id: String
    let title: String
    let items: [String]
}

struct ServiceTypeSection: Identifiable {
    let id: String
    let title: String
    let items: [ServiceTypeInfo]
}

struct ServiceInstanceSection: Identifiable {
    let id: String
    let title: String
    let items: [DiscoveredService]
}

@MainActor
final class BonjourDiscoveryViewModel: ObservableObject {
    let manager = BonjourDiscoveryManager.shared
    
    // Scoped Published State
    @Published var domains: [String] = []
    @Published var serviceTypes: [ServiceTypeInfo] = []
    @Published var instances: [DiscoveredService] = []
    @Published var resolvedService: ResolvedServiceInfo? = nil
    @Published var isSearching = false
    @Published var resolveError: String? = nil
    
    // Sort & Group Settings
    @Published var domainSortAscending = true
    @Published var domainGroupByFirstLetter = false
    
    @Published var serviceTypeSortOption: ServiceTypeSortOption = .nameAscending
    @Published var serviceTypeGroupOption: ServiceTypeGroupOption = .none
    
    @Published var instanceSortOption: ServiceInstanceSortOption = .nameAscending
    @Published var instanceGroupOption: ServiceInstanceGroupOption = .none
    
    @Published var sortAddressesV4First = true
    
    private var periodicTimerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.domains = manager.domains
        self.serviceTypes = manager.serviceTypes
        self.instances = manager.instances
        self.resolvedService = manager.resolvedService
        self.isSearching = manager.isSearching
        self.resolveError = manager.resolveError
        
        manager.$domains
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$domains)
            
        manager.$serviceTypes
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$serviceTypes)
            
        manager.$instances
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$instances)
            
        manager.$resolvedService
            .receive(on: DispatchQueue.main)
            .assign(to: &$resolvedService)
            
        manager.$isSearching
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$isSearching)
            
        manager.$resolveError
            .receive(on: DispatchQueue.main)
            .assign(to: &$resolveError)
    }
    
    // Processed Domains
    var processedDomains: [DomainSection] {
        let sorted = domains.sorted {
            domainSortAscending ? $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                                : $0.localizedCaseInsensitiveCompare($1) == .orderedDescending
        }
        
        if domainGroupByFirstLetter {
            let grouped = Dictionary(grouping: sorted) { domain -> String in
                String(domain.prefix(1)).uppercased()
            }
            let keys = grouped.keys.sorted {
                domainSortAscending ? $0 < $1 : $0 > $1
            }
            return keys.map { DomainSection(id: "group_\($0)", title: "\($0) (\(grouped[$0]?.count ?? 0))", items: grouped[$0] ?? []) }
        } else {
            return [DomainSection(id: "all_domains", title: "Browsable Domains", items: sorted)]
        }
    }
    
    // Processed Service Types
    var processedServiceTypes: [ServiceTypeSection] {
        let sorted = serviceTypes.sorted { lhs, rhs in
            switch serviceTypeSortOption {
            case .nameAscending:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case .nameDescending:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedDescending
            case .rawType:
                return lhs.rawType.localizedCaseInsensitiveCompare(rhs.rawType) == .orderedAscending
            }
        }
        
        switch serviceTypeGroupOption {
        case .none:
            let title = "\(serviceTypes.count) Service\(serviceTypes.count == 1 ? "" : "s") Found"
            return [ServiceTypeSection(id: "all_types", title: title, items: sorted)]
            
        case .protocolType:
            let tcpItems = sorted.filter { $0.rawType.contains("_tcp") }
            let udpItems = sorted.filter { $0.rawType.contains("_udp") }
            let otherItems = sorted.filter { !$0.rawType.contains("_tcp") && !$0.rawType.contains("_udp") }
            
            var sections: [ServiceTypeSection] = []
            if !tcpItems.isEmpty {
                sections.append(ServiceTypeSection(id: "tcp_types", title: "TCP Services (\(tcpItems.count))", items: tcpItems))
            }
            if !udpItems.isEmpty {
                sections.append(ServiceTypeSection(id: "udp_types", title: "UDP Services (\(udpItems.count))", items: udpItems))
            }
            if !otherItems.isEmpty {
                sections.append(ServiceTypeSection(id: "other_types", title: "Other Services (\(otherItems.count))", items: otherItems))
            }
            return sections
            
        case .category:
            let recognized = sorted.filter { $0.friendlyName != nil }
            let unknown = sorted.filter { $0.friendlyName == nil }
            
            var sections: [ServiceTypeSection] = []
            if !recognized.isEmpty {
                sections.append(ServiceTypeSection(id: "recognized_types", title: "Recognized Services (\(recognized.count))", items: recognized))
            }
            if !unknown.isEmpty {
                sections.append(ServiceTypeSection(id: "unknown_types", title: "Other / Raw Services (\(unknown.count))", items: unknown))
            }
            return sections
            
        case .firstLetter:
            let grouped = Dictionary(grouping: sorted) { item -> String in
                String(item.displayName.prefix(1)).uppercased()
            }
            let keys = grouped.keys.sorted {
                serviceTypeSortOption == .nameDescending ? $0 > $1 : $0 < $1
            }
            return keys.map { ServiceTypeSection(id: "group_\($0)", title: "\($0) (\(grouped[$0]?.count ?? 0))", items: grouped[$0] ?? []) }
        }
    }
    
    // Processed Service Instances
    var processedInstances: [ServiceInstanceSection] {
        let sorted = instances.sorted { lhs, rhs in
            switch instanceSortOption {
            case .nameAscending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .nameDescending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            }
        }
        
        switch instanceGroupOption {
        case .none:
            let title = "\(instances.count) Instance\(instances.count == 1 ? "" : "s")"
            return [ServiceInstanceSection(id: "all_instances", title: title, items: sorted)]
            
        case .firstLetter:
            let grouped = Dictionary(grouping: sorted) { item -> String in
                String(item.name.prefix(1)).uppercased()
            }
            let keys = grouped.keys.sorted {
                instanceSortOption == .nameDescending ? $0 > $1 : $0 < $1
            }
            return keys.map { ServiceInstanceSection(id: "group_\($0)", title: "\($0) (\(grouped[$0]?.count ?? 0))", items: grouped[$0] ?? []) }
        }
    }
    
    // Sorted Addresses
    var sortedAddresses: [String] {
        guard let resolved = resolvedService else { return [] }
        return resolved.addresses.sorted { a, b in
            let aIsV6 = a.contains(":")
            let bIsV6 = b.contains(":")
            if aIsV6 != bIsV6 {
                return sortAddressesV4First ? !aIsV6 : aIsV6
            }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
    
    // Periodic Background Refresh Actions
    func startDomainPeriodicRefresh(interval: TimeInterval = AppConstants.Bonjour.periodicRefreshInterval) {
        stopPeriodicRefresh()
        manager.discoverDomains(clearExisting: domains.isEmpty)
        
        periodicTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self = self, !Task.isCancelled else { break }
                self.manager.discoverDomains(clearExisting: false)
            }
        }
    }
    
    func startServiceTypePeriodicRefresh(in domain: String, interval: TimeInterval = AppConstants.Bonjour.periodicRefreshInterval) {
        stopPeriodicRefresh()
        manager.discoverServiceTypes(in: domain, clearExisting: serviceTypes.isEmpty)
        
        periodicTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self = self, !Task.isCancelled else { break }
                self.manager.discoverServiceTypes(in: domain, clearExisting: false)
            }
        }
    }
    
    func startInstancePeriodicRefresh(ofType type: String, in domain: String, interval: TimeInterval = AppConstants.Bonjour.periodicRefreshInterval) {
        stopPeriodicRefresh()
        manager.discoverInstances(ofType: type, inDomain: domain, clearExisting: true)
        
        periodicTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self = self, !Task.isCancelled else { break }
                self.manager.discoverInstances(ofType: type, inDomain: domain, clearExisting: false)
            }
        }
    }
    
    func stopPeriodicRefresh() {
        periodicTimerTask?.cancel()
        periodicTimerTask = nil
    }
    
    func refreshDomains() {
        manager.discoverDomains(clearExisting: false)
    }
    
    func refreshServiceTypes(in domain: String) {
        manager.discoverServiceTypes(in: domain, clearExisting: false)
    }
    
    func refreshInstances(ofType type: String, in domain: String) {
        manager.discoverInstances(ofType: type, inDomain: domain, clearExisting: false)
    }
    
    func stopDomainSearch() {
        stopPeriodicRefresh()
        manager.stopDomainSearch()
    }
    
    func stopTypeSearch() {
        stopPeriodicRefresh()
        manager.stopTypeSearch()
    }
    
    func stopInstanceSearch() {
        stopPeriodicRefresh()
        manager.stopInstanceSearch()
    }
    
    func resolveService(_ service: DiscoveredService) {
        manager.resolveService(service)
    }
    
    func stopResolving() {
        manager.stopResolving()
    }
    
    func copyAllResolvedInfo() -> String? {
        guard let resolved = resolvedService else { return nil }
        
        var lines: [String] = []
        lines.append("Service: \(resolved.name)")
        lines.append("Type: \(resolved.type)")
        lines.append("Domain: \(resolved.domain)")
        lines.append("Hostname: \(resolved.hostname)")
        lines.append("Port: \(resolved.port)")
        lines.append("")
        
        if !resolved.addresses.isEmpty {
            lines.append("Addresses:")
            for addr in sortedAddresses {
                lines.append("  \(addr)")
            }
            lines.append("")
        }
        
        if !resolved.txtRecords.isEmpty {
            lines.append("TXT Records:")
            for record in resolved.txtRecords {
                lines.append("  \(record.key) = \(record.value)")
            }
        }
        
        let text = lines.joined(separator: "\n")
        UIPasteboard.general.string = text
        return text
    }
}
