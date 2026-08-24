//
//  BonjourDiscoveryView.swift
//  SideStore
//
//  Created by Magesh K on 4/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

// MARK: - Root View (Domains List)

// Entry point: discovers and lists browsable Bonjour domains.
// Tapping a domain navigates to its service types.
struct BonjourDiscoveryView: View {
    @StateObject private var viewModel = BonjourDiscoveryViewModel()
    @State private var selectedDomain: String? = nil
    @State private var isAutoRefreshEnabled = true
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.isSearching && viewModel.domains.isEmpty {
                ProgressView("Searching for domains…")
            } else if !viewModel.isSearching && viewModel.domains.isEmpty {
                emptyState
            } else {
                domainsList
            }
        }
        .navigationTitle("Discovery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isAutoRefreshEnabled.toggle()
                    if isAutoRefreshEnabled {
                        viewModel.startDomainPeriodicRefresh()
                    } else {
                        viewModel.stopPeriodicRefresh()
                    }
                } label: {
                    Image(systemName: isAutoRefreshEnabled ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                        .foregroundColor(isAutoRefreshEnabled ? .accentColor : .secondary)
                }
                
                Menu {
                    Menu {
                        SwiftUI.Button {
                            viewModel.domainGroupByFirstLetter = false
                        } label: {
                            Label("None", systemImage: !viewModel.domainGroupByFirstLetter ? "checkmark" : "")
                        }
                        SwiftUI.Button {
                            viewModel.domainGroupByFirstLetter = true
                        } label: {
                            Label("First Letter", systemImage: viewModel.domainGroupByFirstLetter ? "checkmark" : "")
                        }
                    } label: {
                        Label("Group By", systemImage: "rectangle.3.group")
                    }
                    
                    Menu {
                        SwiftUI.Button {
                            viewModel.domainSortAscending = true
                        } label: {
                            Label("Name (A to Z)", systemImage: viewModel.domainSortAscending ? "checkmark" : "")
                        }
                        SwiftUI.Button {
                            viewModel.domainSortAscending = false
                        } label: {
                            Label("Name (Z to A)", systemImage: !viewModel.domainSortAscending ? "checkmark" : "")
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onAppear {
            selectedDomain = nil
            if isAutoRefreshEnabled {
                viewModel.startDomainPeriodicRefresh()
            }
        }
        .onDisappear {
            viewModel.stopDomainSearch()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Domains Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Make sure you're connected to a local network.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                viewModel.startDomainPeriodicRefresh()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                Text("Ensure **Local Network Access** is provided otherwise this function may not work as intended since it is based on L N A...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("**Settings -> apps -> SideStore -> LocalNetworkAccess = toggle on**")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var domainsList: some View {
        List {
            ForEach(viewModel.processedDomains) { section in
                Section(header: Text(section.title)) {
                    ForEach(section.items, id: \.self) { domain in
                        NavigationLink(
                            destination: Group {
                                if let active = selectedDomain {
                                    ServiceTypesView(domain: active, viewModel: viewModel)
                                }
                            },
                            tag: domain,
                            selection: $selectedDomain
                        ) {
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 28)
                                Text(domain)
                                    .font(.body)
                            }
                        }
                        .id(domain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.refreshDomains()
        }
    }
}


// MARK: - Service Types View

// Lists all service types discovered in a given domain.
// Tapping a type navigates to its instances.
struct ServiceTypesView: View {
    let domain: String
    @ObservedObject var viewModel: BonjourDiscoveryViewModel
    @State private var selectedType: String? = nil
    @State private var isAutoRefreshEnabled = true
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.isSearching && viewModel.serviceTypes.isEmpty {
                ProgressView("Searching for service types…")
            } else if !viewModel.isSearching && viewModel.serviceTypes.isEmpty {
                emptyState
            } else {
                serviceTypesList
            }
        }
        .navigationTitle(domain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isAutoRefreshEnabled.toggle()
                    if isAutoRefreshEnabled {
                        viewModel.startServiceTypePeriodicRefresh(in: domain)
                    } else {
                        viewModel.stopPeriodicRefresh()
                    }
                } label: {
                    Image(systemName: isAutoRefreshEnabled ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                        .foregroundColor(isAutoRefreshEnabled ? .accentColor : .secondary)
                }
                
                Menu {
                    Menu {
                        ForEach(ServiceTypeGroupOption.allCases, id: \.self) { opt in
                            SwiftUI.Button {
                                viewModel.serviceTypeGroupOption = opt
                            } label: {
                                Label(opt.rawValue, systemImage: viewModel.serviceTypeGroupOption == opt ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Group By", systemImage: "rectangle.3.group")
                    }
                    
                    Menu {
                        ForEach(ServiceTypeSortOption.allCases, id: \.self) { opt in
                            SwiftUI.Button {
                                viewModel.serviceTypeSortOption = opt
                            } label: {
                                Label(opt.rawValue, systemImage: viewModel.serviceTypeSortOption == opt ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onAppear {
            selectedType = nil
            if isAutoRefreshEnabled {
                viewModel.startServiceTypePeriodicRefresh(in: domain)
            }
        }
        .onDisappear {
            viewModel.stopTypeSearch()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Services Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("No Bonjour services are currently advertised in this domain.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                viewModel.startServiceTypePeriodicRefresh(in: domain)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                Text("Ensure **Local Network Access** is provided otherwise this function may not work as intended since it is based on L N A...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("**Settings -> apps -> SideStore -> LocalNetworkAccess = toggle on**")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var serviceTypesList: some View {
        List {
            ForEach(viewModel.processedServiceTypes) { section in
                Section(
                    header: Text(section.title),
                    footer: (section.id == viewModel.processedServiceTypes.last?.id) ? searchingFooter : nil
                ) {
                    ForEach(section.items) { typeInfo in
                        NavigationLink(
                            destination: Group {
                                if let activeType = selectedType,
                                   let matchedInfo = section.items.first(where: { $0.rawType == activeType }) ?? viewModel.serviceTypes.first(where: { $0.rawType == activeType }) {
                                    ServiceInstancesView(
                                        serviceType: matchedInfo.rawType,
                                        domain: domain,
                                        friendlyName: matchedInfo.friendlyName,
                                        viewModel: viewModel
                                    )
                                }
                            },
                            tag: typeInfo.rawType,
                            selection: $selectedType
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: typeInfo.friendlyName != nil ? "checkmark.seal.fill" : "questionmark.circle")
                                    .foregroundColor(typeInfo.friendlyName != nil ? .green : .orange)
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    if let friendly = typeInfo.friendlyName {
                                        Text(friendly)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(typeInfo.rawType)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    } else {
                                        Text(typeInfo.rawType)
                                            .font(.body)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .id(typeInfo.rawType)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.refreshServiceTypes(in: domain)
        }
    }
    
    @ViewBuilder
    private var searchingFooter: some View {
        if viewModel.isSearching {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Searching…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}


// MARK: - Service Instances View

// Lists all discovered instances of a specific service type.
// Tapping an instance navigates to its resolved details.
struct ServiceInstancesView: View {
    let serviceType: String
    let domain: String
    let friendlyName: String?
    @ObservedObject var viewModel: BonjourDiscoveryViewModel
    @State private var selectedInstanceId: String? = nil
    @State private var isAutoRefreshEnabled = true
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.isSearching && viewModel.instances.isEmpty {
                ProgressView("Searching for instances…")
            } else if !viewModel.isSearching && viewModel.instances.isEmpty {
                emptyState
            } else {
                instancesList
            }
        }
        .navigationTitle(friendlyName ?? serviceType)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isAutoRefreshEnabled.toggle()
                    if isAutoRefreshEnabled {
                        viewModel.startInstancePeriodicRefresh(ofType: serviceType, in: domain)
                    } else {
                        viewModel.stopPeriodicRefresh()
                    }
                } label: {
                    Image(systemName: isAutoRefreshEnabled ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                        .foregroundColor(isAutoRefreshEnabled ? .accentColor : .secondary)
                }
                
                Menu {
                    Menu {
                        ForEach(ServiceInstanceGroupOption.allCases, id: \.self) { opt in
                            SwiftUI.Button {
                                viewModel.instanceGroupOption = opt
                            } label: {
                                Label(opt.rawValue, systemImage: viewModel.instanceGroupOption == opt ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Group By", systemImage: "rectangle.3.group")
                    }
                    
                    Menu {
                        ForEach(ServiceInstanceSortOption.allCases, id: \.self) { opt in
                            SwiftUI.Button {
                                viewModel.instanceSortOption = opt
                            } label: {
                                Label(opt.rawValue, systemImage: viewModel.instanceSortOption == opt ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onAppear {
            selectedInstanceId = nil
            if isAutoRefreshEnabled {
                viewModel.startInstancePeriodicRefresh(ofType: serviceType, in: domain)
            }
        }
        .onDisappear {
            viewModel.stopInstanceSearch()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Instances Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("No devices are currently advertising this service.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                viewModel.startInstancePeriodicRefresh(ofType: serviceType, in: domain)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                Text("Ensure **Local Network Access** is provided otherwise this function may not work as intended since it is based on L N A...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("**Settings -> apps -> SideStore -> LocalNetworkAccess = toggle on**")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var instancesList: some View {
        List {
            ForEach(viewModel.processedInstances) { section in
                Section(
                    header: Text(section.title),
                    footer: (section.id == viewModel.processedInstances.last?.id) ? searchingFooter : nil
                ) {
                    ForEach(section.items) { instance in
                        NavigationLink(
                            destination: Group {
                                if let activeId = selectedInstanceId,
                                   let matchedInstance = section.items.first(where: { $0.id == activeId }) ?? viewModel.instances.first(where: { $0.id == activeId }) {
                                    ServiceDetailView(service: matchedInstance, viewModel: viewModel)
                                }
                            },
                            tag: instance.id,
                            selection: $selectedInstanceId
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 28)
                                
                                Text(instance.name)
                                    .font(.body)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                        .id(instance.id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.refreshInstances(ofType: serviceType, in: domain)
        }
    }
    
    @ViewBuilder
    private var searchingFooter: some View {
        if viewModel.isSearching {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Searching…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}


// MARK: - Service Detail View

// Shows full resolved details of a service: hostname, port, IP addresses, TXT records.
struct ServiceDetailView: View {
    let service: DiscoveredService
    @ObservedObject var viewModel: BonjourDiscoveryViewModel
    @State private var showCopyConfirmation = false
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if let resolved = viewModel.resolvedService {
                resolvedContent(resolved)
            } else if let error = viewModel.resolveError {
                errorState(error)
            } else {
                loadingState
            }
        }
        .navigationTitle("Service Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if viewModel.resolvedService != nil {
                    Menu {
                        SwiftUI.Button {
                            viewModel.sortAddressesV4First = true
                        } label: {
                            Label("IPv4 First", systemImage: viewModel.sortAddressesV4First ? "checkmark" : "")
                        }
                        SwiftUI.Button {
                            viewModel.sortAddressesV4First = false
                        } label: {
                            Label("IPv6 First", systemImage: !viewModel.sortAddressesV4First ? "checkmark" : "")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    
                    SwiftUI.Button("Copy") {
                        if viewModel.copyAllResolvedInfo() != nil {
                            withAnimation(.spring(response: 0.3)) {
                                showCopyConfirmation = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.spring(response: 0.3)) {
                                    showCopyConfirmation = false
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.resolveService(service)
        }
        .onDisappear {
            viewModel.stopResolving()
        }
    }
    
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Resolving service…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Resolution Failed")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                viewModel.resolveService(service)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
        }
    }
    
    private func resolvedContent(_ resolved: ResolvedServiceInfo) -> some View {
        List {
            // Service Name Header
            Section {
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "bonjour")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                    Text(resolved.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            // Connection Info
            Section(header: Text("Connection")) {
                DetailRow(label: "Hostname", value: resolved.hostname)
                DetailRow(label: "Port", value: "\(resolved.port)")
                DetailRow(label: "Type", value: resolved.type)
                DetailRow(label: "Domain", value: resolved.domain)
            }
            
            // IP Addresses
            if !resolved.addresses.isEmpty {
                Section(header: Text("Addresses (\(resolved.addresses.count))")) {
                    ForEach(viewModel.sortedAddresses, id: \.self) { address in
                        HStack {
                            Image(systemName: address.contains(":") ? "6.circle" : "4.circle")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text(address)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .contextMenu {
                            SwiftUI.Button {
                                UIPasteboard.general.string = address
                            } label: {
                                Label("Copy Address", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
            
            // TXT Records
            if !resolved.txtRecords.isEmpty {
                Section(header: Text("TXT Record (\(resolved.txtRecords.count))")) {
                    ForEach(resolved.txtRecords, id: \.key) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.key)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(record.value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            SwiftUI.Button {
                                UIPasteboard.general.string = "\(record.key) = \(record.value)"
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.resolveService(service)
        }
        .overlay(alignment: .bottom) {
            if showCopyConfirmation {
                copiedBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private var copiedBanner: some View {
        Text("Copied to Clipboard")
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.accentColor)
            )
            .padding(.bottom, 16)
    }
}


// MARK: - Detail Row

// A simple key-value row with context menu for copying
private struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .lineLimit(nil)
        }
        .padding(.vertical, 2)
        .contextMenu {
            SwiftUI.Button {
                UIPasteboard.general.string = value
            } label: {
                Label("Copy \(label)", systemImage: "doc.on.doc")
            }
        }
    }
}
