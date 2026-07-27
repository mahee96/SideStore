//
//  AnisetteServerList.swift
//  SideStore
//
//  Created by ny on 6/18/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import UIKit
import SwiftUI
import AltStoreCore

typealias SUIButton = SwiftUI.Button

// MARK: - AnisetteServerData
struct AnisetteServerData: Codable {
    let servers: [Server]
}

// MARK: - Server
struct Server: Codable, Identifiable, Hashable {
    var id: String { address }
    var name: String
    var address: String
}
final class AnisetteViewModel: ObservableObject {
    static let defaultSource = "https://servers.sidestore.io/servers.json"

    @Published var source: String = defaultSource
    @Published var items: [AnisetteServerItem] = []
    @Published var showHiddenServers: Bool = false
    @Published var isOfflineMode: Bool = false
    @Published var importedFileName: String? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    var hasHiddenItems: Bool {
        items.contains(where: \.isHidden)
    }

    var visibleItems: [AnisetteServerItem] {
        showHiddenServers ? items : items.filter { !$0.isHidden }
    }

    init() {
        let customSource = UserDefaults.standard.menuAnisetteList
        if !customSource.isEmpty {
            self.source = customSource
        }
        Task { @MainActor in
            self.isOfflineMode = await AnisetteServersManager.shared.isOfflineMode
            self.importedFileName = await AnisetteServersManager.shared.importedFileName
            self.items = await AnisetteServersManager.shared.loadLocalServers()
        }
    }

    @MainActor
    @discardableResult
    func fetchServers(forceRemote: Bool = false) async -> Result<[AnisetteServerItem], Error> {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let isOffline = await AnisetteServersManager.shared.isOfflineMode
        let filename = await AnisetteServersManager.shared.importedFileName
        self.isOfflineMode = isOffline
        self.importedFileName = filename

        if isOffline && !forceRemote {
            let offline = await AnisetteServersManager.shared.loadLocalServers()
            self.items = offline
            return .success(offline)
        }

        do {
            let merged = try await withThrowingTaskGroup(of: [AnisetteServerItem].self) { group in
                group.addTask {
                    return try await AnisetteServersManager.shared.syncWithRemote(sourceURLString: self.source, forceRemote: forceRemote)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "Server list fetch timed out after 5 seconds."])
                }
                guard let result = try await group.next() else {
                    throw URLError(.timedOut)
                }
                group.cancelAll()
                return result
            }
            self.items = merged
            debugLog("AnisetteViewModel: Server list sync completed for sourceURL: \(self.source)")
            return .success(merged)
        } catch {
            let offline = await AnisetteServersManager.shared.loadLocalServers()
            self.items = offline
            if let urlErr = error as? URLError, urlErr.code == .timedOut {
                self.errorMessage = "Connection timed out (5s limit). Check your network connection or server URL."
            } else {
                self.errorMessage = error.localizedDescription
            }
            debugLog("AnisetteViewModel: Server list sync Failed: \(error)")
            return .failure(error)
        }
    }

    @MainActor
    func importFile(url: URL) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let imported = try await AnisetteServersManager.shared.importFromFile(url: url)
            self.items = imported
            self.isOfflineMode = true
            self.importedFileName = url.lastPathComponent
            debugLog("AnisetteViewModel: Imported servers from file: \(url.lastPathComponent)")
        } catch {
            self.errorMessage = "Failed to import file: \(error.localizedDescription)"
            debugLog("AnisetteViewModel: Import error: \(error)")
        }
    }

    func exportCatalog(unmodified: Bool = false) async -> URL? {
        guard let data = await AnisetteServersManager.shared.exportCatalogData(unmodified: unmodified) else { return nil }
        let baseName = (await AnisetteServersManager.shared.importedFileName) ?? "anisette-servers.json"
        let nameWithoutExt = (baseName as NSString).deletingPathExtension
        let ext = (baseName as NSString).pathExtension.isEmpty ? "json" : (baseName as NSString).pathExtension
        let suffix = unmodified ? "-unmodified" : "-customized"
        let filename = "\(nameWithoutExt)\(suffix).\(ext)"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    @MainActor
    func resetToOriginalState() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let resetItems = try await AnisetteServersManager.shared.resetToOriginalState()
            self.items = resetItems
            debugLog("AnisetteViewModel: Reset catalog to original uncustomized state.")
        } catch {
            self.errorMessage = "Failed to reset: \(error.localizedDescription)"
            debugLog("AnisetteViewModel: Reset error: \(error)")
        }
    }

    @MainActor
    func clearImportedFile() async {
        await AnisetteServersManager.shared.clearOfflineFileMode()
        self.isOfflineMode = false
        self.importedFileName = nil
        self.source = AnisetteViewModel.defaultSource
        await fetchServers(forceRemote: true)
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        if showHiddenServers {
            items.move(fromOffsets: source, toOffset: destination)
        } else {
            let visibleIndices = items.enumerated().compactMap { index, item in
                item.isHidden ? nil : index
            }

            guard !visibleIndices.isEmpty else { return }

            let actualSourceIndices = source.compactMap { $0 < visibleIndices.count ? visibleIndices[$0] : nil }
            let actualDestinationIndex: Int
            if destination >= visibleIndices.count {
                actualDestinationIndex = items.count
            } else {
                actualDestinationIndex = visibleIndices[destination]
            }

            let movedItems = actualSourceIndices.map { items[$0] }
            for index in actualSourceIndices.sorted(by: >) {
                items.remove(at: index)
            }

            var targetIndex = actualDestinationIndex
            let removedBeforeTarget = actualSourceIndices.filter { $0 < actualDestinationIndex }.count
            targetIndex -= removedBeforeTarget
            targetIndex = max(0, min(items.count, targetIndex))

            items.insert(contentsOf: movedItems, at: targetIndex)
        }

        let currentItems = items
        Task {
            await AnisetteServersManager.shared.saveLocalServers(currentItems)
        }
    }

    func toggleHide(item: AnisetteServerItem) {
        if let index = items.firstIndex(where: { $0.address == item.address }) {
            items[index].isHidden.toggle()
            let currentItems = items
            Task {
                await AnisetteServersManager.shared.saveLocalServers(currentItems)
            }
        }
    }

    static func getListOfServers(serverSource: String) async throws -> [Server] {
        var aniServers: [Server] = []

        guard let url = URL(string: serverSource) else {
            return aniServers
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "AnisetteViewModel: ServerError", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed with HTTP status \(statusCode)."])
        }

        let decoder = Foundation.JSONDecoder()
        if let serversObj = try? decoder.decode(AnisetteServerData.self, from: data) {
            aniServers.append(contentsOf: serversObj.servers)
        } else if let serversArray = try? decoder.decode([Server].self, from: data) {
            aniServers.append(contentsOf: serversArray)
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for dict in json {
                if let name = dict["name"] as? String, let address = dict["address"] as? String {
                    aniServers.append(Server(name: name, address: address))
                }
            }
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["servers"] as? [[String: Any]] {
            for dict in list {
                if let name = dict["name"] as? String, let address = dict["address"] as? String {
                    aniServers.append(Server(name: name, address: address))
                }
            }
        } else {
            throw NSError(domain: "AnisetteViewModel: ServerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server catalog format from remote URL."])
        }

        debugLog("AnisetteViewModel: JSON Decode successful for sourceURL: \(serverSource) servers count: \(aniServers.count)")
        return aniServers
    }
}

struct AnisetteServersView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = AnisetteViewModel()
    @State private var selectedServerURL: String = ""
    @State private var showingResetAlert = false
    @State private var showingFileImporter = false
    @State private var showingShareSheet = false
    @State private var exportFileURL: URL? = nil
    @State private var isEditingURL = false
    @State private var editingURLText: String = ""

    var selected: String?
    var onResetAdiPb: (() -> Void)?

    init(
        selected: String? = nil,
        onResetAdiPb: (() -> Void)? = nil
    ) {
        self.selected = selected
        self.onResetAdiPb = onResetAdiPb
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("Fetching Anisette Servers...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            } else if viewModel.items.isEmpty {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 56))
                        .foregroundColor(.orange)

                    Text("Uh oh! Could not reach servers")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)

                    Text(viewModel.errorMessage ?? "The Anisette server list failed to load or timed out after 5 seconds.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    SwiftUI.Button {
                        Task {
                            await viewModel.fetchServers(forceRemote: true)
                        }
                    } label: {
                        Label("Retry Connection", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            } else {
                List {
                    // Section 1: Server Selection
                    Section {
                        ForEach(viewModel.visibleItems) { item in
                            SwiftUI.Button {
                                selectedServerURL = item.address
                                UserDefaults.standard.menuAnisetteURL = item.address
                                UserDefaults.standard.synchronize()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.name)
                                                .font(.body)
                                                .foregroundColor(item.isHidden ? .secondary : .primary)

                                            if item.isHidden {
                                                Text("Hidden")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                                            }
                                        }

                                        Text(item.address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if selectedServerURL == item.address {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .opacity(item.isHidden ? 0.6 : 1.0)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                SwiftUI.Button {
                                    viewModel.toggleHide(item: item)
                                } label: {
                                    Label(item.isHidden ? "Unhide" : "Hide", systemImage: item.isHidden ? "eye" : "eye.slash")
                                }
                                .tint(item.isHidden ? .blue : .orange)
                            }
                        }
                        .onMove(perform: viewModel.moveItems)
                    } header: {
                        if viewModel.isOfflineMode {
                            HStack(spacing: 6) {
                                Text("Available Servers (OFFLINE)")
                                Image(systemName: "wifi.slash")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                            }
                        } else {
                            Text("Available Servers")
                        }
                    } footer: {
                        Text("Drag to reorder server priority. Swipe left on a server to hide or unhide it.")
                    }

                    // Section 2: Source Configuration
                    Section {
                        if viewModel.isOfflineMode {
                            HStack {
                                Text("Catalog File")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(viewModel.importedFileName ?? "Imported File")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                            .contextMenu {
                                SwiftUI.Button {
                                    Task {
                                        if let url = await viewModel.exportCatalog(unmodified: false) {
                                            exportFileURL = url
                                            showingShareSheet = true
                                        }
                                    }
                                } label: {
                                    Label("Export Current (Customized)", systemImage: "square.and.arrow.up")
                                }

                                SwiftUI.Button {
                                    Task {
                                        if let url = await viewModel.exportCatalog(unmodified: true) {
                                            exportFileURL = url
                                            showingShareSheet = true
                                        }
                                    }
                                } label: {
                                    Label("Export Original (Unmodified)", systemImage: "doc.on.doc")
                                }

                                SwiftUI.Button(role: .destructive) {
                                    Task {
                                        await viewModel.resetToOriginalState()
                                    }
                                } label: {
                                    Label("Reset to Original Catalog", systemImage: "arrow.circlepath")
                                }
                            }

                            SwiftUI.Button("Clear Imported File & Reset to Default URL") {
                                Task {
                                    await viewModel.clearImportedFile()
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.red)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Server List URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if isEditingURL {
                                    TextField("https://...", text: $editingURLText)
                                        .font(.subheadline)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                } else {
                                    Text(viewModel.source)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .padding(.vertical, 2)
                            .contextMenu {
                                SwiftUI.Button {
                                    Task {
                                        if let url = await viewModel.exportCatalog(unmodified: false) {
                                            exportFileURL = url
                                            showingShareSheet = true
                                        }
                                    }
                                } label: {
                                    Label("Export Current (Customized)", systemImage: "square.and.arrow.up")
                                }

                                SwiftUI.Button {
                                    Task {
                                        if let url = await viewModel.exportCatalog(unmodified: true) {
                                            exportFileURL = url
                                            showingShareSheet = true
                                        }
                                    }
                                } label: {
                                    Label("Export Original (Unmodified)", systemImage: "doc.on.doc")
                                }

                                SwiftUI.Button(role: .destructive) {
                                    Task {
                                        await viewModel.resetToOriginalState()
                                    }
                                } label: {
                                    Label("Reset to Original Catalog", systemImage: "arrow.circlepath")
                                }
                            }

                            if viewModel.source != AnisetteViewModel.defaultSource {
                                SwiftUI.Button("Reset Source to Default") {
                                    viewModel.source = AnisetteViewModel.defaultSource
                                    UserDefaults.standard.menuAnisetteList = AnisetteViewModel.defaultSource
                                    Task {
                                        await viewModel.fetchServers(forceRemote: true)
                                    }
                                }
                                .font(.subheadline)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Server Catalog Source")
                            Spacer()
                            if !viewModel.isOfflineMode {
                                SwiftUI.Button(isEditingURL ? "Done" : "Edit") {
                                    if isEditingURL {
                                        isEditingURL = false
                                        let trimmed = editingURLText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty && trimmed != viewModel.source {
                                            viewModel.source = trimmed
                                            UserDefaults.standard.menuAnisetteList = trimmed
                                            Task {
                                                await viewModel.fetchServers(forceRemote: true)
                                            }
                                        }
                                    } else {
                                        editingURLText = viewModel.source
                                        isEditingURL = true
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    } footer: {
                        if viewModel.isOfflineMode {
                            Text("Currently using imported file '\(viewModel.importedFileName ?? "custom.json")'. Press and hold row to export.")
                        } else {
                            Text("URL of the JSON file containing registered Anisette servers. Press and hold row to export.")
                        }
                    }

                    // Section 3: Troubleshooting
                    Section {
                        SwiftUI.Button(role: .destructive) {
                            showingResetAlert = true
                        } label: {
                            HStack {
                                Text("Reset adi.pb")
                                Spacer()
                                Image(systemName: "trash")
                                    .font(.subheadline)
                            }
                        }
                        .alert(isPresented: $showingResetAlert) {
                            Alert(
                                title: Text("Reset adi.pb"),
                                message: Text("Are you sure you want to clear adi.pb from the Keychain? You will need to log back in to Apple ID in SideStore."),
                                primaryButton: .destructive(Text("Reset")) {
                                    #if !DEBUG
                                    if Keychain.shared.adiPb != nil {
                                        Keychain.shared.adiPb = nil
                                    }
                                    #endif
                                    debugLog("Cleared adi.pb from keychain")
                                    onResetAdiPb?()
                                    presentationMode.wrappedValue.dismiss()
                                },
                                secondaryButton: .cancel()
                            )
                        }
                    } header: {
                        Text("Troubleshooting")
                    } footer: {
                        Text("Resetting local Anisette data forces a fresh provisioning flow if authentication is failing.")
                    }

                    // Bottom spacing section
                    Section {
                        Color.clear
                            .frame(height: 100)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.fetchServers(forceRemote: true)
                }
            }
        }
        .navigationTitle("Anisette Servers")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if viewModel.isOfflineMode {
                    SwiftUI.Button {
                        Task {
                            await viewModel.clearImportedFile()
                        }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                } else {
                    SwiftUI.Button {
                        showingFileImporter = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                }

                Menu {
                    if viewModel.hasHiddenItems {
                        SwiftUI.Button {
                            viewModel.showHiddenServers.toggle()
                        } label: {
                            Label(viewModel.showHiddenServers ? "Hide Hidden Items" : "Show Hidden Items", systemImage: viewModel.showHiddenServers ? "eye.slash" : "eye")
                        }
                    }

                    SwiftUI.Button {
                        Task {
                            if let url = await viewModel.exportCatalog(unmodified: false) {
                                exportFileURL = url
                                showingShareSheet = true
                            }
                        }
                    } label: {
                        Label("Export Current (Customized)", systemImage: "square.and.arrow.up")
                    }

                    if viewModel.isOfflineMode {
                        SwiftUI.Button {
                            Task {
                                if let url = await viewModel.exportCatalog(unmodified: true) {
                                    exportFileURL = url
                                    showingShareSheet = true
                                }
                            }
                        } label: {
                            Label("Export Original (Unmodified)", systemImage: "doc.on.doc")
                        }
                    }

                    SwiftUI.Button(role: .destructive) {
                        Task {
                            await viewModel.resetToOriginalState()
                        }
                    } label: {
                        Label("Reset to Original Catalog", systemImage: "arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await viewModel.importFile(url: url)
                    }
                }
            case .failure(let error):
                debugLog("File import failed: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let fileURL = exportFileURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
        .task {
            let active = selected ?? UserDefaults.standard.menuAnisetteURL
            if !active.isEmpty {
                selectedServerURL = active
            }
            await viewModel.fetchServers()
        }
    }
}


