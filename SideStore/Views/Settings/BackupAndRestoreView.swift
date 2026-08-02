//
//  BackupAndRestoreView.swift
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

struct BackupAndRestoreView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: Account, Certificate, & Pairing Data
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACCOUNT, CERTIFICATE, & PAIRING DATA")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button(action: {
                            print("[BackupAndRestoreView] Import Account tapped")
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Import Account")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(action: {
                            print("[BackupAndRestoreView] Export Account tapped")
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Export Account")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                
                // Section 2: Sources Data
                VStack(alignment: .leading, spacing: 8) {
                    Text("SOURCES DATA")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button(action: {
                            print("[BackupAndRestoreView] Import Sources tapped")
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Import Sources")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(action: {
                            print("[BackupAndRestoreView] Export Sources tapped")
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Export Sources")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
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
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}
