//
//  UserCustomizationsView.swift
//  SideStore
//
//  Created by Magesh K on 8/2/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import AltStoreCore

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct UserCustomizationsView: View {
    @State private var customizeAppId: Bool = UserDefaults.standard.customizeAppId
    @State private var customizeAppExtensions: Bool = UserDefaults.standard.customizeAppExtensions
    @State private var isExportResignedAppEnabled: Bool = UserDefaults.standard.isExportResignedAppEnabled
    @State private var enableEMPforWireguard: Bool = UserDefaults.standard.enableEMPforWireguard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: APP & EXTENSIONS CUSTOMIZATION
                VStack(alignment: .leading, spacing: 8) {
                    Text("CUSTOMIZATION OPTIONS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        toggleRow(title: "Customize AppID", isOn: Binding(
                            get: { customizeAppId },
                            set: { newValue in
                                customizeAppId = newValue
                                UserDefaults.standard.customizeAppId = newValue
                            }
                        ))
                        
                        divider
                        
                        toggleRow(title: "Customize App Extensions", isOn: Binding(
                            get: { customizeAppExtensions },
                            set: { newValue in
                                customizeAppExtensions = newValue
                                UserDefaults.standard.customizeAppExtensions = newValue
                            }
                        ))
                        
                        divider
                        
                        toggleRow(title: "Export Resigned Apps", isOn: Binding(
                            get: { isExportResignedAppEnabled },
                            set: { newValue in
                                isExportResignedAppEnabled = newValue
                                UserDefaults.standard.isExportResignedAppEnabled = newValue
                            }
                        ))
                        
                        divider
                        
                        toggleRow(title: "Enable EMP for WireGuard", isOn: Binding(
                            get: { enableEMPforWireguard },
                            set: { newValue in
                                enableEMPforWireguard = newValue
                                UserDefaults.standard.enableEMPforWireguard = newValue
                            }
                        ))
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle("User Customizations")
        .navigationBarTitleDisplayMode(.large)
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}
