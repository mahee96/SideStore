//
//  WirelessPairTargetDialog.swift
//  SideStore
//
//  Created by Magesh K on 24/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

enum SelectedEndpointOption: Hashable {
    case discovered(WirelessPairTarget)
    case configuredFallback
}

struct WirelessPairTargetDialog: View {
    @ObservedObject private var manager = WirelessPairManager.shared
    @Binding var isPresented: Bool
    
    @State private var selectedOption: SelectedEndpointOption = .configuredFallback
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissDialog()
                }
            
            VStack(spacing: 0) {
                headerView
                
                Divider()
                    .padding(.horizontal, 16)
                
                contentScrollView
                    .padding(.vertical, 12)
                
                Divider()
                    .padding(.horizontal, 16)
                
                footerButtons
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.3), radius: 24, x: 0, y: 12)
            )
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .onAppear {
            manager.startDiscovery()
            if let firstTarget = manager.discoveredTargets.first {
                selectedOption = .discovered(firstTarget)
                manager.selectAndResolveTarget(firstTarget)
            } else {
                selectedOption = .configuredFallback
            }
        }
        .onDisappear {
            manager.stopDiscovery()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.76), value: isPresented)
    }
    
    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.accentColor)
            
            Text("Select Pairing Device")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            if manager.isScanning {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                SwiftUI.Button {
                    manager.startDiscovery()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
    
    private var contentScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Section: Discovered Devices
                VStack(alignment: .leading, spacing: 6) {
                    Text("DISCOVERED NEARBY")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                    
                    if manager.discoveredTargets.isEmpty {
                        HStack(spacing: 10) {
                            if manager.isScanning {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Searching local network for devices…")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No pairing targets found via Bonjour.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(manager.discoveredTargets) { target in
                                discoveredTargetRow(for: target)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                // Section: Configured Fallback Endpoint
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONFIGURED ENDPOINT")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                    
                    fallbackEndpointRow
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 280)
    }
    
    private func discoveredTargetRow(for target: WirelessPairTarget) -> some View {
        let isSelected: Bool = {
            if case .discovered(let selected) = selectedOption {
                return selected.id == target.id
            }
            return false
        }()
        
        return SwiftUI.Button {
            selectedOption = .discovered(target)
            manager.selectAndResolveTarget(target)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: target.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(target.typeBadge)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if let model = target.model {
                            Text("• \(model)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if isSelected {
                        if let resolved = manager.resolvedService {
                            Text("\(resolved.hostname):\(resolved.port)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.accentColor)
                        } else {
                            Text("Resolving IP address…")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .accentColor : Color(.tertiaryLabel))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var fallbackEndpointRow: some View {
        let fallback = manager.fallbackConfigEndpoint
        let isSelected: Bool = {
            if case .configuredFallback = selectedOption {
                return true
            }
            return false
        }()
        
        return SwiftUI.Button {
            selectedOption = .configuredFallback
            manager.deselectTarget()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configured Target")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("\(fallback.ip):\(fallback.port)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .accentColor : Color(.tertiaryLabel))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var footerButtons: some View {
        HStack(spacing: 12) {
            SwiftUI.Button("Cancel") {
                dismissDialog()
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            SwiftUI.Button {
                triggerPairingAction()
            } label: {
                Text("Pair")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private func dismissDialog() {
        manager.stopDiscovery()
        isPresented = false
    }
    
    private func triggerPairingAction() {
        dismissDialog()
        
        switch selectedOption {
        case .discovered:
            if let resolved = manager.resolvedService,
               let targetIp = resolved.addresses.first ?? resolved.hostname as String?,
               !targetIp.isEmpty {
                manager.triggerPairing(targetIp: targetIp, targetPort: resolved.port)
            } else {
                let fallback = manager.fallbackConfigEndpoint
                manager.triggerPairing(targetIp: fallback.ip, targetPort: fallback.port)
            }
        case .configuredFallback:
            let fallback = manager.fallbackConfigEndpoint
            manager.triggerPairing(targetIp: fallback.ip, targetPort: fallback.port)
        }
    }
}
