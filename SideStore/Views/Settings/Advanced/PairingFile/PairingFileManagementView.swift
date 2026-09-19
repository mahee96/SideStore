//
//  PairingFileManagementView.swift
//  SideStore
//
//  Created by Magesh K on 19/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import MinimuxerCommon

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct PairingFileManagementView: View {
    @State private var refreshID = UUID()
    @State private var isGlobalHideActive: Bool = true
    @State private var revealedFieldKeys: Set<String> = []
    
    @State private var showFileImporter = false
    @State private var targetImportMode: PairingProtocol? = nil
    
    @State private var modeToDelete: PairingProtocol? = nil
    @State private var showDeleteConfirmation = false
    
    @State private var showingResetAlert = false
    @State private var showingResetCompletedAlert = false
    
    @State private var showingImportErrorAlert = false
    @State private var importErrorMessage = ""

    private let supportedProtocols: [PairingProtocol] = [.lockdown, .rppairing]

    private var currentActiveProtocol: PairingProtocol {
        UserDefaults.standard.activePairingFileType
    }

    private var allowedPairingTypes: [UTType] {
        var types = AppConstants.Pairing.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        types.append(contentsOf: [.propertyList, .xml])
        return types
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                activeProtocolSection
                pairingFilesSection
                pairingMethodsSection
                managementSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .id(refreshID)
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle("Pairing File Management")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isGlobalHideActive.toggle()
                    if isGlobalHideActive {
                        revealedFieldKeys.removeAll()
                    }
                } label: {
                    Image(systemName: isGlobalHideActive ? "eye.slash" : "eye")
                }
                .accessibilityLabel("Toggle Sensitive Information")
            }
        }
        .onAppear {
            refreshView()
        }
        #if !os(tvOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedPairingTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        #endif
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Pairing File?"),
                message: Text("Are you sure you want to delete this pairing file? This will remove the pairing credentials for \(modeToDelete?.rawValue ?? "this mode")."),
                primaryButton: .destructive(Text("Delete")) {
                    if let target = modeToDelete {
                        deletePairingFile(for: target)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showingResetAlert) {
            Alert(
                title: Text("Reset Pairing Files?"),
                message: Text("This will delete all stored pairing files (both Lockdown and Remote Pairing). You will need to re-pair or re-import a pairing file and restart SideStore."),
                primaryButton: .destructive(Text("Delete and Reset")) {
                    resetAllPairingFiles()
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Pairing Files Reset", isPresented: $showingResetCompletedAlert) {
            SwiftUI.Button("OK", role: .cancel) { }
        } message: {
            Text("All pairing files have been reset. Please restart SideStore.")
        }
        .alert("Import Error", isPresented: $showingImportErrorAlert) {
            SwiftUI.Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
    }

    private var activeProtocolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE PROTOCOL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 4)

            HStack {
                Text("Active Protocol")
                    .font(.system(size: 16))
                    .foregroundColor(.white)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(ledColor(for: currentActiveProtocol))
                        .frame(width: 7, height: 7)
                        .shadow(color: ledColor(for: currentActiveProtocol).opacity(0.8), radius: 3)

                    Text(activeProtocolTagText(for: currentActiveProtocol))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    private var pairingFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAIRING FILES")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(supportedProtocols, id: \.rawValue) { proto in
                    pairingFileCard(for: proto)
                }
            }
        }
    }

    private func pairingFileCard(for proto: PairingProtocol) -> some View {
        let fileURL = PairingFileManager.shared.pairingFileURL(for: proto)
        let isInstalled = FileManager.default.fileExists(atPath: fileURL.path)
        let content = isInstalled ? PairingFileManager.shared.fetchPairingFile(for: proto) : nil

        let lockdown = (proto == .lockdown && content != nil) ? PairingFileManager.parsePairingTypes(content: content!).lockdown : nil
        let rp = (proto == .rppairing && content != nil) ? PairingFileManager.parsePairingTypes(content: content!).rp : nil
        let isValid = (proto == .lockdown) ? (lockdown != nil) : (rp != nil)

        let attrs = isInstalled ? ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]) : [:]
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let creationDate = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date)
        let modDate = attrs[.modificationDate] as? Date

        return VStack(alignment: .leading, spacing: 0) {
            if isInstalled {
                NavigationLink(destination: PairingFileDetailView(mode: proto)) {
                    installedCardHeader(for: proto, fileName: fileURL.lastPathComponent, isValid: isValid)
                }
                .contextMenu {
                    if isValid {
                        if proto != currentActiveProtocol {
                            SwiftUI.Button {
                                UserDefaults.standard.activePairingFileType = proto
                                refreshView()
                            } label: {
                                Label("Activate", systemImage: "bolt.fill")
                            }
                        } else {
                            SwiftUI.Button { } label: {
                                Label("Currently Active", systemImage: "checkmark.circle.fill")
                            }
                            .disabled(true)
                        }
                    }

                    SwiftUI.Button {
                        promptImport(for: proto)
                    } label: {
                        Label("Import / Replace File", systemImage: "square.and.arrow.down")
                    }

                    SwiftUI.Button(role: .destructive) {
                        modeToDelete = proto
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Pairing File", systemImage: "trash")
                    }
                }

                divider

                VStack(spacing: 0) {
                    if proto == .rppairing {
                        if let id = rp?.identifier, !id.isEmpty {
                            identifierRow(label: "Identifier", value: id, fieldKey: "rp_identifier")
                            divider
                        }
                        infoRow(label: "Key Material", value: (rp?.publicKey != nil && rp?.privateKey != nil) ? "Public & Private Keys OK" : "Incomplete Keys")
                        divider
                    } else {
                        if let sysBUID = lockdown?.systemBUID, !sysBUID.isEmpty {
                            identifierRow(label: "SystemBUID", value: sysBUID, fieldKey: "lockdown_sysbuid")
                            divider
                        }
                        if let hostID = lockdown?.hostID, !hostID.isEmpty {
                            identifierRow(label: "HostID", value: hostID, fieldKey: "lockdown_hostid")
                            divider
                        }
                        if let udid = lockdown?.udid, !udid.isEmpty {
                            identifierRow(label: "Hardware UDID", value: udid, fieldKey: "lockdown_udid")
                            divider
                        }
                        if let wifi = lockdown?.wifiMACAddress, !wifi.isEmpty {
                            identifierRow(label: "WiFi MAC", value: wifi, fieldKey: "lockdown_wifi")
                            divider
                        }
                    }

                    infoRow(label: "File Size", value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    if let created = creationDate {
                        divider
                        infoRow(label: "Date Created", value: formatDate(created))
                    }
                    if let mod = modDate {
                        divider
                        infoRow(label: "Date Modified", value: formatDate(mod))
                    }
                }
            } else {
                SwiftUI.Button {
                    promptImport(for: proto)
                } label: {
                    missingCardHeader(for: proto, fileName: fileURL.lastPathComponent)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    SwiftUI.Button {
                        promptImport(for: proto)
                    } label: {
                        Label("Import Pairing File", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .background(Color.settingsRowBackground)
        .cornerRadius(14)
    }

    private func installedCardHeader(for proto: PairingProtocol, fileName: String, isValid: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: proto == .rppairing ? "bolt.horizontal.circle.fill" : "lock.shield.fill")
                .font(.system(size: 22))
                .foregroundColor(proto == .rppairing ? .cyan : .green)

            VStack(alignment: .leading, spacing: 2) {
                Text(proto == .rppairing ? "Remote Pairing File" : "Lockdown Pairing File")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text(fileName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            Spacer()

            if proto == currentActiveProtocol {
                Text("Active")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ledColor(for: proto))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ledColor(for: proto).opacity(0.18))
                    .cornerRadius(6)
            }

            if isValid {
                Text("Configured")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
            } else {
                Text("Invalid")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func missingCardHeader(for proto: PairingProtocol, fileName: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: proto == .rppairing ? "bolt.horizontal.circle" : "lock.shield")
                .font(.system(size: 22))
                .foregroundColor(Color.white.opacity(0.3))

            VStack(alignment: .leading, spacing: 2) {
                Text(proto == .rppairing ? "Remote Pairing File" : "Lockdown Pairing File")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.8))

                Text(fileName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.4))
            }

            Spacer()

            Text("Missing")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.15))
                .cornerRadius(6)

            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func identifierRow(label: String, value: String, fieldKey: String) -> some View {
        let isRevealed = !isGlobalHideActive || revealedFieldKeys.contains(fieldKey)
        let displayValue = isRevealed ? value : "••••••••••••••••"

        return SwiftUI.Button {
            toggleReveal(for: fieldKey)
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.6))
                Spacer()
                Text(displayValue)
                    .font(.system(size: 13, weight: .medium, design: isRevealed ? .monospaced : .default))
                    .foregroundColor(Color.white.opacity(0.9))
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
        .buttonStyle(.plain)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var pairingMethodsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAIRING METHODS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                NavigationLink(destination: WirelessPairView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Wireless Pairing")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                }
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANAGEMENT")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                SwiftUI.Button(action: {
                    showingResetAlert = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.red)
                        Text("Reset Pairing Files")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                }
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)

            Text("Resetting pairing files removes stored Lockdown and Remote Pairing credentials. You will need to re-pair or re-import a pairing file and restart SideStore.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.5))
                .padding(.horizontal, 4)
                .padding(.top, 4)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func ledColor(for proto: PairingProtocol) -> Color {
        switch proto {
        case .lockdown:
            return .green
        case .rppairing:
            return .cyan
        case .unknown:
            return .orange
        }
    }

    private func activeProtocolTagText(for proto: PairingProtocol) -> String {
        switch proto {
        case .lockdown:
            return ".lockdown"
        case .rppairing:
            return ".rppairing"
        case .unknown:
            return ".unknown"
        }
    }

    private func toggleReveal(for fieldKey: String) {
        if revealedFieldKeys.contains(fieldKey) {
            revealedFieldKeys.remove(fieldKey)
        } else {
            revealedFieldKeys.insert(fieldKey)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func refreshView() {
        refreshID = UUID()
    }

    private func promptImport(for mode: PairingProtocol) {
        targetImportMode = mode
        showFileImporter = true
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let isSecured = url.startAccessingSecurityScopedResource()
            defer {
                if isSecured {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else {
                importErrorMessage = "Could not read the selected pairing file."
                showingImportErrorAlert = true
                return
            }
            do {
                if let target = targetImportMode {
                    try PairingFileManager.shared.savePairingFile(contents: content, for: target)
                    UserDefaults.standard.activePairingFileType = target
                } else {
                    try PairingFileManager.shared.savePairingFile(contents: content)
                }
                refreshView()
            } catch {
                importErrorMessage = "Failed to import pairing file: \(error.localizedDescription)"
                showingImportErrorAlert = true
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showingImportErrorAlert = true
        }
    }

    private func deletePairingFile(for mode: PairingProtocol) {
        PairingFileManager.shared.deletePairingFile(for: mode)
        if mode == UserDefaults.standard.activePairingFileType {
            let other: PairingProtocol = (mode == .rppairing) ? .lockdown : .rppairing
            let otherPath = PairingFileManager.shared.pairingFileURL(for: other).path
            if FileManager.default.fileExists(atPath: otherPath) {
                UserDefaults.standard.activePairingFileType = other
            }
        }
        refreshView()
    }

    private func resetAllPairingFiles() {
        let fm = FileManager.default
        let files = [
            AppConstants.Pairing.legacyPairingFileName,
            AppConstants.Pairing.lockdownPairingFileName,
            AppConstants.Pairing.remotePairingFileName
        ]
        for name in files {
            let path = fm.documentsDirectory.appendingPathComponent(name)
            if fm.fileExists(atPath: path.path) {
                try? fm.removeItem(at: path)
            }
        }
        UserDefaults.standard.isPairingReset = true
        refreshView()
        showingResetCompletedAlert = true
    }
}
