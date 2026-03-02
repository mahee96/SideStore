//
//  VPNConfiguration.swift
//  AltStore
//
//  Created by Magesh K on 02/03/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

private typealias SButton = SwiftUI.Button

struct VPNConfigurationView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var config = TunnelConfig.shared

    @State private var showNetworkWarning = false

    var body: some View {
        List {
            Section(header: Text("Discovered from network")) {
                Group {
                    networkConfigRow(label: "Tunnel IP", text: $config.deviceIP, editable: false)
                    networkConfigRow(label: "Device IP", text: $config.fakeIP, editable: false)
                    networkConfigRow(label: "Subnet Mask", text: $config.subnetMask, editable: false)
                }
            }
            
            Section {
                networkConfigRow(
                    label: "Device IP",
                    text: Binding<String?>(
                        get: { config.overrideFakeIP },
                        set: { config.overrideFakeIP = $0 ?? "" }
                    ),
                    editable: true
                )
                networkConfigRow(label: "Active", text: .constant(config.overrideActive), editable: false)
            } header: {
                Text("Override Configuration")
            } footer: {
                HStack(alignment: .top, spacing: 0) {
                    Text("Note: ")
                    Text("if the override configuration is invalid or unusable SideStore may use auto-discovered configuration as fallback")
                }
            }
        }
        .alert(isPresented: $showNetworkWarning) {
            Alert(
                title: Text("Warning"),
                message: Text("Changing tunnel IP settings can disrupt your network connection. Proceed only if you are sure of what you are doing."),
                dismissButton: .cancel(Text("I Understand")) {
                    config.shownTunnelAlert = true
                }
            )
        }
        .navigationTitle("VPN Configuration")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SButton("Confirm") {
                    commitChanges()
                }
            }
        }
    }

    private func commitChanges() {
        TunnelConfig.shared.commitFakeIP()
        bindTunnelConfig()
    }
    
    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }

    private func networkConfigRow(
        label: LocalizedStringKey,
        text: Binding<String?>,
        editable: Bool
    ) -> some View {

        let proxy = Binding<String>(
            get: { text.wrappedValue ?? "N/A" },
            set: { text.wrappedValue = $0.isEmpty || $0 == "N/A" ? nil : $0 }
        )

        return HStack {
            Text(label)
                .foregroundColor(editable ? .primary : .gray)
            Spacer()
            TextField(label, text: proxy)
                .multilineTextAlignment(.trailing)
                .foregroundColor(editable ? .secondary : .gray)
                .disabled(!editable)
                .keyboardType(.numbersAndPunctuation)
                .onChange(of: proxy.wrappedValue) { newValue in
                    guard editable else { return }

                    if !config.shownTunnelAlert {
                        showNetworkWarning = true
                    }

                    proxy.wrappedValue =
                        newValue.filter { "0123456789.".contains($0) }
                }
        }
    }
}


final class TunnelConfig: ObservableObject {

    static let shared = TunnelConfig()

    @Published var deviceIP: String?
    @Published var subnetMask: String?
    @Published var fakeIP: String?
    @Published var overrideFakeIP: String = UserDefaults.standard.string(forKey: "TunnelOverrideFakeIP") ?? "10.7.0.1" {
        didSet { UserDefaults.standard.set(overrideFakeIP, forKey: "TunnelOverrideFakeIP") }
    }
    @Published var overrideEffective: Bool = false

    var overrideActive: String {
        ((fakeIP?.isEmpty == false) && !overrideFakeIP.isEmpty && fakeIP == overrideFakeIP) ? "Yes" : "No"
    }

    @Published var shownTunnelAlert: Bool = UserDefaults.standard.bool(forKey: "shownTunnelAlert") {
        didSet { UserDefaults.standard.set(shownTunnelAlert, forKey: "shownTunnelAlert") }
    }

    func commitFakeIP() {
        fakeIP = overrideFakeIP
    }
}
