//
//  WirelessPairView.swift
//  SideStore
//
//  Created by Magesh K on 04/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

enum WirelessPairMode: String, CaseIterable, Identifiable {
    case client = "Pair Target"
    case responder = "Advertise"
    
    var id: String { rawValue }
}

private struct PendingPairConfirmation: Identifiable {
    var id: String { "\(ip):\(port)" }
    let hostName: String
    let ip: String
    let port: UInt16
}

struct WirelessPairView: View {
    @ObservedObject private var manager = WirelessPairManager.shared
    @State private var mode: WirelessPairMode = .client
    @State private var pendingConfirmation: PendingPairConfirmation? = nil
    @State private var showConfirmation = false
    
    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.68)
    private let pulse = Animation.interactiveSpring(response: 1.5, dampingFraction: 0.55)
    
    var body: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $mode) {
                ForEach(WirelessPairMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            if mode == .client {
                clientModeView
            } else {
                responderModeView
            }
        }
        .navigationTitle("Wireless Pairing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.startDiscovery()
        }
        .onDisappear {
            manager.stopDiscovery()
        }
        .alert(isPresented: $showConfirmation) {
            Alert(
                title: Text("Trigger Wireless Pairing"),
                message: Text("Do you want to pair with \(pendingConfirmation?.hostName ?? "target") at \(pendingConfirmation?.ip ?? ""):\(String(pendingConfirmation?.port ?? 0))?"),
                primaryButton: .default(Text("Pair")) {
                    if let target = pendingConfirmation {
                        withAnimation(spring) {
                            manager.triggerPairing(
                                targetIp: target.ip,
                                targetPort: target.port
                            )
                        }
                    }
                    pendingConfirmation = nil
                },
                secondaryButton: .cancel {
                    pendingConfirmation = nil
                }
            )
        }
    }
    
    private var clientModeView: some View {
        VStack(spacing: 16) {
            if let resolved = manager.resolvedService {
                selectedServiceDetailView(resolved: resolved)
            } else {
                serviceListView
            }
            
            if manager.isAdvertising || manager.errorMessage != nil || manager.pairedDevice != nil {
                VStack(spacing: 6) {
                    Text(manager.statusText)
                        .font(.headline)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(manager.subStatusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.vertical, 8)
            }
            
            if let pin = manager.pinCode {
                pinDisplayView(pin: pin)
            }
            
            if let error = manager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer(minLength: 8)
        }
    }
    
    private var serviceListView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("DISCOVERED MDNS SERVICES")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.secondary)
                
                Spacer()
                
                if manager.isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 4)
                }
                
                SwiftUI.Button(action: {
                    manager.startDiscovery()
                }) {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            if manager.discoveredTargets.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    if manager.isScanning {
                        ProgressView("Scanning local network for pairing services...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("No Pairing Services Found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Open Remote Pairing settings on your target device.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        let fallback = manager.fallbackConfigEndpoint
                        VStack(spacing: 10) {
                            Text("OR USE ACTIVE CONFIGURATION")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(1)
                            
                            CachedConfigEndpointCard(ip: fallback.ip, port: fallback.port) {
                                pendingConfirmation = PendingPairConfirmation(
                                    hostName: "Active Config",
                                    ip: fallback.ip,
                                    port: fallback.port
                                )
                                showConfirmation = true
                            }
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(manager.discoveredTargets) { target in
                            WirelessPairTargetCard(target: target) {
                                withAnimation(spring) {
                                    manager.selectAndResolveTarget(target)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private func selectedServiceDetailView(resolved: ResolvedServiceInfo) -> some View {
        VStack(spacing: 12) {
            HStack {
                SwiftUI.Button(action: {
                    withAnimation(spring) {
                        manager.deselectTarget()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("All Services")
                            .font(.system(size: 15, weight: .medium))
                    }
                }
                
                Spacer()
                
                Text(resolved.type)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 26))
                    .foregroundColor(.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Host: \(resolved.hostname)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    if let modelRecord = resolved.txtRecords.first(where: { $0.key.lowercased() == "model" }) {
                        Text("Model: \(modelRecord.value)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            
            let endpoints = resolved.addresses.isEmpty ? [resolved.hostname] : resolved.addresses
            
            HStack {
                Text("RESOLVED ENDPOINTS (\(endpoints.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Tap to pair")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(endpoints, id: \.self) { address in
                        ResolvedEndpointCard(
                            address: address,
                            port: resolved.port,
                            hostname: resolved.hostname
                        ) {
                            pendingConfirmation = PendingPairConfirmation(
                                hostName: resolved.name,
                                ip: address,
                                port: resolved.port
                            )
                            showConfirmation = true
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var responderModeView: some View {
        VStack(spacing: 24) {
            // Pulsing Status Orb
            ZStack {
                // Outer breathing glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: manager.isAdvertising ? [Color.accentColor.opacity(0.25), Color.clear] : [Color.gray.opacity(0.1), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 100
                        )
                    )
                    .frame(width: 220, height: 220)
                    .scaleEffect(manager.isAdvertising ? 1.2 : 1.0)
                    .opacity(manager.isAdvertising ? 1.0 : 0.5)
                    .animation(manager.isAdvertising ? pulse.repeatForever(autoreverses: true) : .default, value: manager.isAdvertising)
                
                // Secondary pulsing ring
                Circle()
                    .stroke(manager.isAdvertising ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 2)
                    .frame(width: 140, height: 140)
                    .scaleEffect(manager.isAdvertising ? 1.15 : 1.0)
                    .opacity(manager.isAdvertising ? 0.8 : 0.0)
                    .animation(manager.isAdvertising ? pulse.delay(0.2).repeatForever(autoreverses: true) : .default, value: manager.isAdvertising)

                // Central Orb
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: manager.isAdvertising ? [Color.accentColor, Color.accentColor.opacity(0.8)] : [Color.gray, Color.gray.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                    .shadow(color: manager.isAdvertising ? Color.accentColor.opacity(0.5) : Color.clear, radius: 15)
                
                Group {
                    if manager.isAdvertising {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "wifi.slash")
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.white)
            }
            .frame(height: 220)
            .padding(.top, 20)
            .padding(.bottom, 20)
            
            // Status Info
            VStack(spacing: 8) {
                Text(manager.statusText)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                if manager.serviceID == nil {
                    Text(manager.subStatusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            // Connection Details Card
            if let serviceID = manager.serviceID, let port = manager.port {
                ConnectionDetailsCard(serviceID: serviceID, port: port)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))

                HStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                    Text("Ensure both devices are on the same Wi-Fi network.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            
            // PIN Display
            if let pin = manager.pinCode {
                VStack(spacing: 12) {
                    Text("PAIRING CODE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .tracking(3)
                    
                    HStack(spacing: 14) {
                        ForEach(Array(pin.enumerated()), id: \.offset) { _, char in
                            Text(String(char))
                                .font(.system(size: 34, weight: .bold, design: .monospaced))
                                .frame(width: 52, height: 68)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 3)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(gradient: Gradient(colors: [Color.accentColor.opacity(0.5), Color.clear]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                        }
                    }
                }
                .padding(.vertical, 16)
                .transition(.scale.combined(with: .opacity))
            }
            
            // Error Display
            if let error = manager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }
            
            Spacer()
            
            // Main Button
            SwiftUI.Button(action: togglePairing) {
                HStack {
                    if manager.isAdvertising {
                        Text("Stop Advertising")
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("Start Pairing")
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(manager.isAdvertising ? Color.red : Color.accentColor)
                .clipShape(Capsule())
                .shadow(color: (manager.isAdvertising ? Color.red : Color.accentColor).opacity(0.3), radius: 10, y: 5)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: manager.isAdvertising)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .navigationTitle("Wireless Pairing")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func pinDisplayView(pin: String) -> some View {
        VStack(spacing: 10) {
            Text("PAIRING CODE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(3)
            
            HStack(spacing: 12) {
                ForEach(Array(pin.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .frame(width: 46, height: 60)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5))
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func togglePairing() {
        withAnimation(spring) {
            manager.togglePairing()
        }
    }
}

struct WirelessPairTargetCard: View {
    let target: WirelessPairTarget
    let onSelect: () -> Void
    
    var body: some View {
        SwiftUI.Button(action: onSelect) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: target.iconName)
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(target.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(target.typeBadge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 8) {
                        Text(target.rawType)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        if let model = target.model {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(model)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ResolvedEndpointCard: View {
    let address: String
    let port: UInt16
    let hostname: String
    let onSelect: () -> Void
    
    var isIPv6: Bool { address.contains(":") }
    
    var body: some View {
        SwiftUI.Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: isIPv6 ? "network" : "point.filled.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(address):\(String(port))")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(isIPv6 ? "IPv6" : "IPv4")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    Text(hostname)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CachedConfigEndpointCard: View {
    let ip: String
    let port: UInt16
    let onSelect: () -> Void
    
    var body: some View {
        SwiftUI.Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Active Cached Endpoint")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("Offline")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    Text("\(ip):\(String(port))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ConnectionDetailsCard: View {
    let serviceID: String
    let port: Int
    
    var rows: [(label: String, value: String)] {[
        ("Device ID", serviceID),
        ("Port", String(port))
    ]}
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack{
                Image(systemName: "network")
                    .foregroundColor(.accentColor)
                Text("Connection Details")
                    .font(.headline)
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 0){
                ForEach(0..<rows.count, id: \.self) { index in
                    let (label, value) = rows[index]
                    let isFirst = index == 0
                    let isLast = index == rows.count - 1
                    
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(value)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if !isLast {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(
                        RoundedCorner(
                            radius: 20,
                            corners: {
                                var c: UIRectCorner = []
                                if isFirst { c.formUnion([.topLeft, .topRight]) }
                                if isLast { c.formUnion([.bottomLeft, .bottomRight]) }
                                return c
                            }()
                        )
                    )
                    .contentShape(Rectangle())
                    .contextMenu {
                        SwiftUI.Button {
                            UIPasteboard.general.string = value
                        } label: {
                            Label("Copy \(label)", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Selective Corner Rounding Shape
private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
