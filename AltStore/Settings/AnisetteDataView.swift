//  AnisetteDataView.swift
//  AltStore
//
//  Created by Magesh K on 31/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
class AnisetteDataViewModel: ObservableObject {
    @Published var clientInfo: String = ""
    @Published var userAgent: String = ""
    @Published var customDeviceID: String = ""
    @Published var customLocalUserID: String = ""
    @Published var customLocale: String = ""
    @Published var customTimeZone: String = ""
    
    @Published var isOfflineMode: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var successMessage: String? = nil
    
    init() {
        Task {
            await loadData()
        }
    }
    
    func loadData() async {
        isOfflineMode = AnisetteConfigManager.shared.isOfflineMode
        let config = await AnisetteConfigManager.shared.loadConfig()
        clientInfo = config.clientInfo
        userAgent = config.userAgent
        customDeviceID = config.customDeviceID ?? ""
        customLocalUserID = config.customLocalUserID ?? ""
        customLocale = config.customLocale ?? ""
        customTimeZone = config.customTimeZone ?? ""
    }
    
    func save() async {
        AnisetteConfigManager.shared.isOfflineMode = isOfflineMode
        let config = AnisetteConfig(
            clientInfo: clientInfo,
            userAgent: userAgent,
            customDeviceID: customDeviceID.isEmpty ? nil : customDeviceID,
            customLocalUserID: customLocalUserID.isEmpty ? nil : customLocalUserID,
            customLocale: customLocale.isEmpty ? nil : customLocale,
            customTimeZone: customTimeZone.isEmpty ? nil : customTimeZone
        )
        await AnisetteConfigManager.shared.saveConfig(config)
        successMessage = "Saved configuration successfully."
    }
    
    func reset() async {
        let config = await AnisetteConfigManager.shared.resetToDefaults()
        clientInfo = config.clientInfo
        userAgent = config.userAgent
        customDeviceID = ""
        customLocalUserID = ""
        customLocale = ""
        customTimeZone = ""
        successMessage = "Reset to default configuration."
    }
    
    func importJSON(url: URL) async {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        defer { isLoading = false }
        
        do {
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gotAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let config = try await AnisetteConfigManager.shared.importFromFile(url: url)
            clientInfo = config.clientInfo
            userAgent = config.userAgent
            customDeviceID = config.customDeviceID ?? ""
            customLocalUserID = config.customLocalUserID ?? ""
            customLocale = config.customLocale ?? ""
            customTimeZone = config.customTimeZone ?? ""
            successMessage = "Imported successfully from '\(url.lastPathComponent)'."
        } catch {
            errorMessage = "Failed to import configuration: \(error.localizedDescription)"
        }
    }
    
    func exportJSON() async -> URL? {
        guard let data = await AnisetteConfigManager.shared.exportConfigData() else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("anisette-config.json")
        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            errorMessage = "Failed to export configuration: \(error.localizedDescription)"
            return nil
        }
    }
    
    func fetchFreshFromServer() async {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        defer { isLoading = false }
        
        do {
            let activeServer = UserDefaults.standard.menuAnisetteURL
            guard !activeServer.isEmpty, let url = URL(string: activeServer) else {
                throw NSError(domain: "AnisetteDataViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active anisette server URL configured."])
            }
            
            let clientInfoURL = url.appendingPathComponent("v3").appendingPathComponent("client_info")
            var request = URLRequest(url: clientInfoURL)
            request.timeoutInterval = 10
            
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: String],
                  let fetchedClientInfo = json["client_info"],
                  let fetchedUserAgent = json["user_agent"] else {
                throw NSError(domain: "AnisetteDataViewModel", code: -2, userInfo: [NSLocalizedDescriptionKey: "Server response is not a valid V3 client info JSON."])
            }
            
            clientInfo = fetchedClientInfo
            userAgent = fetchedUserAgent
            let config = AnisetteConfig(
                clientInfo: clientInfo,
                userAgent: userAgent,
                customDeviceID: customDeviceID.isEmpty ? nil : customDeviceID,
                customLocalUserID: customLocalUserID.isEmpty ? nil : customLocalUserID,
                customLocale: customLocale.isEmpty ? nil : customLocale,
                customTimeZone: customTimeZone.isEmpty ? nil : customTimeZone
            )
            await AnisetteConfigManager.shared.saveConfig(config)
            successMessage = "Fetched fresh config from '\(url.host ?? "server")'."
        } catch {
            errorMessage = "Failed to fetch from server: \(error.localizedDescription)"
        }
    }
}

struct AnisetteDataView: View {
    @StateObject private var viewModel = AnisetteDataViewModel()
    @State private var showingResetAlert = false
    @State private var showingFileImporter = false
    @State private var showingShareSheet = false
    @State private var exportFileURL: URL? = nil
    @State private var isCopied = false
    
    var rawJSONString: String {
        var dict = [
            "client_info": viewModel.clientInfo,
            "user_agent": viewModel.userAgent
        ]
        if !viewModel.customDeviceID.isEmpty { dict["custom_device_id"] = viewModel.customDeviceID }
        if !viewModel.customLocalUserID.isEmpty { dict["custom_local_user_id"] = viewModel.customLocalUserID }
        if !viewModel.customLocale.isEmpty { dict["custom_locale"] = viewModel.customLocale }
        if !viewModel.customTimeZone.isEmpty { dict["custom_time_zone"] = viewModel.customTimeZone }
        
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
    
    var body: some View {
        List {
            // Section 1: Mode Selection
            Section {
                Toggle(isOn: $viewModel.isOfflineMode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use Offline Config File")
                            .font(.body)
                        Text("Bypasses fetching client info from servers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: viewModel.isOfflineMode) { newValue in
                    Task {
                        await viewModel.save()
                    }
                }
            } header: {
                Text("Operational Mode")
            } footer: {
                Text("When enabled, SideStore uses the locally saved JSON configuration parameters for all authentication headers without making client_info requests to servers.")
            }
            
            // Section 2: Header Customization
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Client Info (X-Mme-Client-Info)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $viewModel.clientInfo)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 80)
                        .padding(4)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(6)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("User Agent")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $viewModel.userAgent)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 80)
                        .padding(4)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(6)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Device ID Override (Optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("System Generated", text: $viewModel.customDeviceID)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(6)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Local User ID Override (Optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("System Generated", text: $viewModel.customLocalUserID)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(6)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Locale Override (Optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("e.g. en_US", text: $viewModel.customLocale)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(6)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Time Zone Override (Optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("e.g. UTC, GMT", text: $viewModel.customTimeZone)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(6)
                }
                .padding(.vertical, 4)
                
                SwiftUI.Button {
                    Task {
                        await viewModel.save()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Save Changes")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(viewModel.clientInfo.isEmpty || viewModel.userAgent.isEmpty)
            } header: {
                Text("Custom Parameters")
            }
            
            // Section 3: Raw JSON Preview
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("JSON Representation")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        SwiftUI.Button {
                            UIPasteboard.general.string = rawJSONString
                            withAnimation {
                                isCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    isCopied = false
                                }
                            }
                        } label: {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.footnote)
                                .foregroundColor(isCopied ? .green : .accentColor)
                        }
                    }
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(rawJSONString)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(6)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Preview")
            }
            
            // Section 4: File & Actions Integration
            Section {
                SwiftUI.Button {
                    Task {
                        await viewModel.fetchFreshFromServer()
                    }
                } label: {
                    Label("Fetch Fresh from Active Server", systemImage: "arrow.clockwise")
                }
                
                SwiftUI.Button {
                    showingFileImporter = true
                } label: {
                    Label("Import Config JSON", systemImage: "square.and.arrow.down")
                }
                
                SwiftUI.Button {
                    Task {
                        if let url = await viewModel.exportJSON() {
                            exportFileURL = url
                            showingShareSheet = true
                        }
                    }
                } label: {
                    Label("Export Config JSON", systemImage: "square.and.arrow.up")
                }
                
                SwiftUI.Button(role: .destructive) {
                    showingResetAlert = true
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.circlepath")
                        .foregroundColor(.red)
                }
                .alert("Reset to Defaults?", isPresented: $showingResetAlert) {
                    SwiftUI.Button("Reset", role: .destructive) {
                        Task {
                            await viewModel.reset()
                        }
                    }
                    SwiftUI.Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will restore the client headers to the default recommended macOS values.")
                }
            } header: {
                Text("Actions")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Client Config")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                        .shadow(radius: 10)
                }
            }
        )
        .overlay(
            VStack {
                Spacer()
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                viewModel.errorMessage = nil
                            }
                        }
                } else if let success = viewModel.successMessage {
                    Text(success)
                        .font(.subheadline)
                        .padding()
                        .background(Color.green.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                viewModel.successMessage = nil
                            }
                        }
                }
            }
        )
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await viewModel.importJSON(url: url)
                    }
                }
            case .failure(let error):
                viewModel.errorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let fileURL = exportFileURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
    }
}
