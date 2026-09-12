//
//  DevicesListView.swift
//  SideStore
//
//  Created by Magesh K on 2/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

enum ActiveDeviceAlert: Identifiable {
    case disable(ALTDevice)
    case delete(ALTDevice)

    var id: String {
        switch self {
        case .disable(let dev): return "disable-\(dev.identifier)"
        case .delete(let dev): return "delete-\(dev.identifier)"
        }
    }
}

struct DevicesListView: View {
    @ObservedObject var viewModel: DeveloperServicesViewModel
    weak var presentingViewController: UIViewController?

    @State private var searchText = ""
    @State private var showRegisterSheet = false
    @State private var newDeviceName = ""
    @State private var newDeviceUDID = ""
    @State private var selectedDeviceType: ALTDeviceType = DeveloperPortalProxy.currentDeviceType
    @State private var isFetchingUDID = false

    @State private var deviceToEdit: ALTDevice? = nil
    @State private var editDeviceName = ""
    @State private var showSheetDeleteAlert = false
    @State private var showSheetDisableAlert = false

    @State private var activeAlert: ActiveDeviceAlert? = nil

    private var filteredDevices: [ALTDevice] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.devices
        }
        return viewModel.devices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.identifier.localizedCaseInsensitiveContains(searchText) ||
            $0.type.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section(header: Text(localized("Registered Devices (\(viewModel.devices.count))")), footer: Text(localized("Devices registered on your developer team can run development-signed apps. Tap any device to edit its name, disable, or delete it."))) {
                if filteredDevices.isEmpty {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        Text(searchText.isEmpty ? localized("No devices registered on Developer Portal.") : localized("No matching devices found."))
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ForEach(filteredDevices, id: \.self) { device in
                        SwiftUI.Button {
                            editDeviceName = device.name
                            deviceToEdit = device
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(device.name.isEmpty ? localized("Device") : device.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if device.status == "d" {
                                        Text(localized("Disabled"))
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.red.opacity(0.15))
                                            .foregroundColor(.red)
                                            .cornerRadius(6)
                                    }
                                    Text(device.type.displayName)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .foregroundColor(.secondary)
                                        .cornerRadius(6)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(device.identifier)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        #if !os(tvOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            SwiftUI.Button(role: .destructive) {
                                activeAlert = .delete(device)
                            } label: {
                                Label(localized("Delete"), systemImage: "trash")
                            }

                            if device.status != "d" {
                                SwiftUI.Button {
                                    activeAlert = .disable(device)
                                } label: {
                                    Label(localized("Disable"), systemImage: "slash.circle")
                                }
                                .tint(.orange)
                            }

                            SwiftUI.Button {
                                editDeviceName = device.name
                                deviceToEdit = device
                            } label: {
                                Label(localized("Edit"), systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        #endif
                        .contextMenu {
                            SwiftUI.Button {
                                editDeviceName = device.name
                                deviceToEdit = device
                            } label: {
                                Label(localized("Edit Name"), systemImage: "pencil")
                            }
                            #if !os(tvOS)
                            SwiftUI.Button {
                                UIPasteboard.general.string = device.identifier
                            } label: {
                                Label(localized("Copy UDID"), systemImage: "doc.on.doc")
                            }
                            #endif
                            if device.status != "d" {
                                SwiftUI.Button {
                                    activeAlert = .disable(device)
                                } label: {
                                    Label(localized("Disable Device"), systemImage: "slash.circle")
                                }
                            }
                            SwiftUI.Button(role: .destructive) {
                                activeAlert = .delete(device)
                            } label: {
                                Label(localized("Delete Device"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(localized("Search Devices")))
        #else
        .listStyle(GroupedListStyle())
        #endif
        .navigationTitle(localized("Devices"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    newDeviceName = ""
                    newDeviceUDID = ""
                    selectedDeviceType = .iphone
                    showRegisterSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.fetchDevices(presentingViewController: presentingViewController, isPullToRefresh: true)
        }
        .sheet(isPresented: $showRegisterSheet) {
            NavigationView {
                Form {
                    Section(header: Text(localized("Device Information")), footer: Text(localized("UDID is a 25-character or 40-character unique device identifier."))) {
                        TextField(localized("Device Name"), text: $newDeviceName)
                        TextField(localized("Device UDID"), text: $newDeviceUDID)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Picker(localized("Device Type"), selection: $selectedDeviceType) {
                            Text(localized("iPhone")).tag(ALTDeviceType.iphone)
                            Text(localized("iPad")).tag(ALTDeviceType.ipad)
                            Text(localized("Apple TV")).tag(ALTDeviceType.appleTV)
                            Text(localized("Apple Watch")).tag(ALTDeviceType.appleWatch)
                            Text(localized("Mac")).tag(ALTDeviceType.mac)
                            Text(localized("Vision Pro")).tag(ALTDeviceType.visionPro)
                        }
                    }

                    Section {
                        SwiftUI.Button {
                            #if !os(tvOS)
                            newDeviceName = UIDevice.current.name
                            if UIDevice.current.userInterfaceIdiom == .pad {
                                selectedDeviceType = .ipad
                            } else {
                                selectedDeviceType = .iphone
                            }
                            #else
                            newDeviceName = "Apple TV"
                            selectedDeviceType = .appleTV
                            #endif
                        } label: {
                            HStack {
                                Image(systemName: "pencil")
                                Text(localized("Fill Current Device Name"))
                            }
                        }

                        SwiftUI.Button {
                            Task {
                                isFetchingUDID = true
                                defer { isFetchingUDID = false }
                                var udid = try? await fetchUDID()
                                if udid == nil || udid?.isEmpty == true {
                                    udid = try? await fetchUDID(useStatic: true)
                                }
                                if let foundUDID = udid, !foundUDID.isEmpty, foundUDID != "XXXXX-XXXX-XXXXX-XXXX" {
                                    newDeviceUDID = foundUDID
                                    if newDeviceName.isEmpty {
                                        #if !os(tvOS)
                                        newDeviceName = UIDevice.current.name
                                        #else
                                        newDeviceName = "Apple TV"
                                        #endif
                                    }
                                    #if !os(tvOS)
                                    if UIDevice.current.userInterfaceIdiom == .pad {
                                        selectedDeviceType = .ipad
                                    } else {
                                        selectedDeviceType = .iphone
                                    }
                                    #endif
                                    viewModel.showToastMessage(localized("Fetched Device UDID: \(foundUDID.prefix(8))..."))
                                } else {
                                    viewModel.showToastMessage(localized("Current Device UDID not available"))
                                }
                            }
                        } label: {
                            HStack {
                                if isFetchingUDID {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                } else {
                                    Image(systemName: "iphone.and.arrow.forward")
                                }
                                Text(localized("Fetch Current Device UDID"))
                            }
                        }
                        .disabled(isFetchingUDID)
                    }
                }
                .navigationTitle(localized("Register Device"))
                .navigationBarItems(
                    leading: SwiftUI.Button(localized("Cancel")) {
                        showRegisterSheet = false
                    },
                    trailing: SwiftUI.Button(localized("Register")) {
                        let name = newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let udid = newDeviceUDID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !udid.isEmpty else { return }
                        Task {
                            let success = await viewModel.registerDevice(name: name, identifier: udid, type: selectedDeviceType, presentingViewController: presentingViewController)
                            if success {
                                showRegisterSheet = false
                            }
                        }
                    }
                    .disabled(newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              newDeviceUDID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              viewModel.isActionLoading)
                )
                .developerServicesToast(viewModel: viewModel)
            }
        }
        .sheet(item: $deviceToEdit) { device in
            NavigationView {
                Form {
                    Section(header: Text(localized("Device Name"))) {
                        TextField(localized("Device Name"), text: $editDeviceName)
                    }

                    Section(header: Text(localized("Device Identifier (UDID)"))) {
                        Text(device.identifier.isEmpty ? localized("Not Available") : device.identifier)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Section(header: Text(localized("Device Details"))) {
                        InfoRow(label: localized("Type"), value: device.type.displayName)
                        InfoRow(label: localized("Status"), value: device.status == "d" ? localized("Disabled") : localized("Active"), valueColor: device.status == "d" ? .red : .green)
                        if let devID = device.deviceID, !devID.isEmpty {
                            InfoRow(label: localized("Portal ID"), value: devID)
                        }
                    }

                    Section {
                        if device.status != "d" {
                            SwiftUI.Button {
                                showSheetDisableAlert = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Image(systemName: "slash.circle")
                                    Text(localized("Disable Device"))
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .foregroundColor(.orange)
                            }
                        }

                        SwiftUI.Button(role: .destructive) {
                            showSheetDeleteAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "trash")
                                Text(localized("Delete Device"))
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle(localized("Edit Device"))
                .navigationBarItems(
                    leading: SwiftUI.Button(localized("Cancel")) {
                        deviceToEdit = nil
                    },
                    trailing: SwiftUI.Button(localized("Save")) {
                        let trimmed = editDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task {
                            let success = await viewModel.updateDevice(device, newName: trimmed, presentingViewController: presentingViewController)
                            if success {
                                deviceToEdit = nil
                            }
                        }
                    }
                    .disabled(editDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              editDeviceName == device.name ||
                              viewModel.isActionLoading)
                )
                .alert(isPresented: $showSheetDisableAlert) {
                    Alert(
                        title: Text(localized("Disable Device?")),
                        message: Text(localized("Are you sure you want to disable '\(device.name)' on the Apple Developer Portal? Disabled devices will not be included in newly generated provisioning profiles.")),
                        primaryButton: .default(Text(localized("Disable"))) {
                            Task {
                                let success = await viewModel.disableDevice(device, presentingViewController: presentingViewController)
                                if success {
                                    deviceToEdit = nil
                                }
                            }
                        },
                        secondaryButton: .cancel()
                    )
                }
                .alert(isPresented: $showSheetDeleteAlert) {
                    Alert(
                        title: Text(localized("Delete Device?")),
                        message: Text(localized("Are you sure you want to delete '\(device.name)' (\(device.identifier)) from the Apple Developer Portal?")),
                        primaryButton: .destructive(Text(localized("Delete"))) {
                            Task {
                                let success = await viewModel.deleteDevice(device, presentingViewController: presentingViewController)
                                if success {
                                    deviceToEdit = nil
                                }
                            }
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .disable(let device):
                return Alert(
                    title: Text(localized("Disable Device?")),
                    message: Text(localized("Are you sure you want to disable '\(device.name)' on the Apple Developer Portal? Disabled devices will not be included in newly generated provisioning profiles.")),
                    primaryButton: .default(Text(localized("Disable"))) {
                        Task {
                            _ = await viewModel.disableDevice(device, presentingViewController: presentingViewController)
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .delete(let device):
                return Alert(
                    title: Text(localized("Delete Device?")),
                    message: Text(localized("Are you sure you want to delete '\(device.name)' (\(device.identifier)) from the Apple Developer Portal?")),
                    primaryButton: .destructive(Text(localized("Delete"))) {
                        Task {
                            _ = await viewModel.deleteDevice(device, presentingViewController: presentingViewController)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .developerServicesToast(viewModel: viewModel)
    }
}
