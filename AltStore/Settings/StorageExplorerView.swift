//
//  StorageExplorerView.swift
//  AltStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - Clipboard Singleton

@MainActor
public final class StorageExplorerClipboard: ObservableObject {
    public static let shared = StorageExplorerClipboard()
    
    @Published public var copiedURL: URL? = nil
    
    private init() {}
    
    public func clear() {
        self.copiedURL = nil
    }
}

// MARK: - Storage Location Model

public struct StorageLocation: Identifiable, Hashable {
    public var id: String { url.path }
    public let name: String
    public let subtitle: String
    public let iconName: String
    public let url: URL
}

// MARK: - Storage Explorer Item Model

public struct StorageExplorerItem: Identifiable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public var size: Int64
    public var itemCount: Int
    public let modificationDate: Date
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
}

// MARK: - Sorting & Grouping Enums

public enum StorageSortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case date = "Date Modified"
    case size = "Size"
    case type = "Type"
    
    public var id: String { rawValue }
}

// MARK: - Directory Explorer ViewModel

@MainActor
public final class StorageExplorerViewModel: ObservableObject {
    public let currentURL: URL
    
    @Published public var items: [StorageExplorerItem] = []
    @Published public var searchText: String = ""
    @Published public var sortOption: StorageSortOption = .name
    @Published public var sortAscending: Bool = true
    @Published public var groupFoldersFirst: Bool = true
    @Published public var isLoading: Bool = false
    
    @Published public var isSelectionMode: Bool = false
    @Published public var selectedURLs: Set<URL> = []
    
    @Published public var currentFolderSize: Int64 = 0
    @Published public var freeDiskSpaceString: String = ""
    
    @Published public var activeAlert: ActiveAlert? = nil
    @Published public var itemToRename: StorageExplorerItem? = nil
    @Published public var renameInput: String = ""
    @Published public var shareURL: URL? = nil
    
    public enum ActiveAlert: Identifiable {
        case confirmSingleDelete(StorageExplorerItem)
        case confirmBulkDelete
        case rename(StorageExplorerItem)
        case error(String)
        
        public var id: String {
            switch self {
            case .confirmSingleDelete(let item): return "singleDelete-\(item.url.path)"
            case .confirmBulkDelete: return "bulkDelete"
            case .rename(let item): return "rename-\(item.url.path)"
            case .error(let msg): return "error-\(msg)"
            }
        }
    }
    
    public init(url: URL) {
        self.currentURL = url
        self.loadContents()
        self.loadDiskSpace()
    }
    
    public func loadDiskSpace() {
        Task.detached {
            let space = await Self.getFreeDiskSpaceString()
            await MainActor.run {
                self.freeDiskSpaceString = space
            }
        }
    }
    
    private static func getFreeDiskSpaceString() -> String {
        do {
            let values = try FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let free = values.volumeAvailableCapacityForImportantUsage {
                return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            } else if let free = values.volumeAvailableCapacity {
                return ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)
            }
        } catch {}
        return "Unknown"
    }
    
    public func loadContents() {
        self.isLoading = true
        let targetURL = self.currentURL
        
        Task.detached {
            var loadedItems: [StorageExplorerItem] = []
            var folderTotalSize: Int64 = 0
            
            do {
                let fileManager = FileManager.default
                let contents = try fileManager.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
                
                for itemURL in contents {
                    let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    let isDir = resourceValues?.isDirectory ?? false
                    let modDate = resourceValues?.contentModificationDate ?? Date()
                    var size: Int64 = Int64(resourceValues?.fileSize ?? 0)
                    var itemCount: Int = 0
                    
                    if isDir {
                        if let subContents = try? fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
                            itemCount = subContents.count
                            var dirSize: Int64 = 0
                            for sub in subContents {
                                if let subVal = try? sub.resourceValues(forKeys: [.fileSizeKey]), let fSize = subVal.fileSize {
                                    dirSize += Int64(fSize)
                                }
                            }
                            size = dirSize
                        }
                    }
                    
                    folderTotalSize += size
                    loadedItems.append(StorageExplorerItem(
                        url: itemURL,
                        name: itemURL.lastPathComponent,
                        isDirectory: isDir,
                        size: size,
                        itemCount: itemCount,
                        modificationDate: modDate
                    ))
                }
            } catch {
                debugLog("[StorageExplorerViewModel] Error reading directory \(targetURL.path): \(error)")
            }
            
            let totalFolderSize = folderTotalSize
            await MainActor.run {
                self.items = loadedItems
                self.currentFolderSize = totalFolderSize
                self.isLoading = false
            }
        }
    }
    
    public var filteredAndSortedItems: [StorageExplorerItem] {
        var result = items
        
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }
        
        result.sort { item1, item2 in
            if groupFoldersFirst && item1.isDirectory != item2.isDirectory {
                return item1.isDirectory && !item2.isDirectory
            }
            
            switch sortOption {
            case .name:
                let comp = item1.name.localizedStandardCompare(item2.name) == .orderedAscending
                return sortAscending ? comp : !comp
            case .date:
                let comp = item1.modificationDate < item2.modificationDate
                return sortAscending ? comp : !comp
            case .size:
                let comp = item1.size < item2.size
                return sortAscending ? comp : !comp
            case .type:
                let ext1 = item1.url.pathExtension
                let ext2 = item2.url.pathExtension
                let comp = ext1.localizedStandardCompare(ext2) == .orderedAscending
                return sortAscending ? comp : !comp
            }
        }
        
        return result
    }
    
    public func delete(item: StorageExplorerItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            self.loadContents()
        } catch {
            self.activeAlert = .error("Failed to delete \(item.name): \(error.localizedDescription)")
        }
    }
    
    public func bulkDeleteSelected() {
        let targets = items.filter { selectedURLs.contains($0.url) }
        var errors: [String] = []
        
        for item in targets {
            do {
                try FileManager.default.removeItem(at: item.url)
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }
        
        self.selectedURLs.removeAll()
        self.isSelectionMode = false
        self.loadContents()
        
        if !errors.isEmpty {
            self.activeAlert = .error("Errors deleting items:\n" + errors.joined(separator: "\n"))
        }
    }
    
    public func rename(item: StorageExplorerItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        
        let destinationURL = item.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        do {
            try FileManager.default.moveItem(at: item.url, to: destinationURL)
            self.loadContents()
        } catch {
            self.activeAlert = .error("Failed to rename \(item.name): \(error.localizedDescription)")
        }
    }
    
    public func copyToClipboard(item: StorageExplorerItem) {
        StorageExplorerClipboard.shared.copiedURL = item.url
    }
    
    public func pasteCopiedItem() {
        guard let sourceURL = StorageExplorerClipboard.shared.copiedURL else { return }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            self.activeAlert = .error("Source item no longer exists.")
            StorageExplorerClipboard.shared.clear()
            return
        }
        
        var destinationURL = self.currentURL.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let nameWithoutExt = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            let newName = ext.isEmpty ? "\(nameWithoutExt) copy" : "\(nameWithoutExt) copy.\(ext)"
            destinationURL = self.currentURL.appendingPathComponent(newName)
        }
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            self.loadContents()
        } catch {
            self.activeAlert = .error("Failed to paste item: \(error.localizedDescription)")
        }
    }
}

// MARK: - Directory Explorer View

public struct DirectoryExplorerView: View {
    @StateObject private var viewModel: StorageExplorerViewModel
    @ObservedObject private var clipboard = StorageExplorerClipboard.shared
    
    public init(url: URL) {
        _viewModel = StateObject(wrappedValue: StorageExplorerViewModel(url: url))
    }
    
    private var folderSummaryString: String {
        let sizeStr = ByteCountFormatter.string(fromByteCount: viewModel.currentFolderSize, countStyle: .file)
        return "\(viewModel.items.count) items (\(sizeStr))"
    }
    
    @ViewBuilder
    private func itemContextMenu(for item: StorageExplorerItem) -> some View {
        if !viewModel.isSelectionMode {
            SwiftUI.Button {
                viewModel.copyToClipboard(item: item)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            SwiftUI.Button {
                viewModel.renameInput = item.name
                viewModel.itemToRename = item
                viewModel.activeAlert = .rename(item)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            if !item.isDirectory {
                SwiftUI.Button {
                    viewModel.shareURL = item.url
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            
            SwiftUI.Button(role: .destructive) {
                viewModel.activeAlert = .confirmSingleDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder
    private var emptyAreaContextMenu: some View {
        if let copiedURL = clipboard.copiedURL {
            let labelText = "Paste “" + copiedURL.lastPathComponent + "”"
            SwiftUI.Button {
                viewModel.pasteCopiedItem()
            } label: {
                Label(labelText, systemImage: "doc.on.clipboard")
            }
        }
    }
    
    @ViewBuilder
    private var trailingToolbarMenu: some View {
        Menu {
            SwiftUI.Button {
                viewModel.isSelectionMode.toggle()
                if !viewModel.isSelectionMode { viewModel.selectedURLs.removeAll() }
            } label: {
                Label(viewModel.isSelectionMode ? "Done Selecting" : "Select", systemImage: "checkmark.circle")
            }
            
            Divider()
            
            Menu("Sort By") {
                ForEach(StorageSortOption.allCases) { option in
                    SwiftUI.Button {
                        if viewModel.sortOption == option {
                            viewModel.sortAscending.toggle()
                        } else {
                            viewModel.sortOption = option
                            viewModel.sortAscending = true
                        }
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if viewModel.sortOption == option {
                                Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            }
            
            Toggle(isOn: $viewModel.groupFoldersFirst) {
                Label("Group Folders First", systemImage: "folder")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    @ViewBuilder
    private var bottomSelectionToolbar: some View {
        let count = viewModel.selectedURLs.count
        HStack {
            SwiftUI.Button(role: .destructive) {
                if !viewModel.selectedURLs.isEmpty {
                    viewModel.activeAlert = .confirmBulkDelete
                }
            } label: {
                Label("Delete (\(count))", systemImage: "trash")
            }
            .disabled(viewModel.selectedURLs.isEmpty)
            
            Spacer()
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.filteredAndSortedItems) { item in
                    ItemRow(item: item, isSelected: viewModel.selectedURLs.contains(item.url), isSelectionMode: viewModel.isSelectionMode) {
                        if viewModel.isSelectionMode {
                            if viewModel.selectedURLs.contains(item.url) {
                                viewModel.selectedURLs.remove(item.url)
                            } else {
                                viewModel.selectedURLs.insert(item.url)
                            }
                        }
                    }
                    .contextMenu {
                        itemContextMenu(for: item)
                    }
                }
                
                // Empty area row at bottom to allow long-press paste
                Section {
                    Color.clear
                        .frame(height: 100)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            emptyAreaContextMenu
                        }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $viewModel.searchText, prompt: "Search files & folders")
            
            // Bottom Status & Storage Information Bar
            VStack(spacing: 4) {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folderSummaryString)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Text("Available Space: \(viewModel.freeDiskSpaceString)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    if clipboard.copiedURL != nil {
                        SwiftUI.Button {
                            viewModel.pasteCopiedItem()
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))
            }
        }
        .navigationTitle(viewModel.currentURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbarMenu
            }
            
            ToolbarItem(placement: .bottomBar) {
                Group {
                    if viewModel.isSelectionMode {
                        bottomSelectionToolbar
                    }
                }
            }
        }
        .sheet(item: Binding(get: {
            viewModel.shareURL.map { ShareItem(url: $0) }
        }, set: { newValue in
            viewModel.shareURL = newValue?.url
        })) { shareItem in
            ActivityViewController(activityItems: [shareItem.url])
        }
        .alert(item: $viewModel.activeAlert) { alertType in
            switch alertType {
            case .confirmSingleDelete(let item):
                return Alert(
                    title: Text("Delete “\(item.name)”?"),
                    message: Text("This item will be permanently removed."),
                    primaryButton: .destructive(Text("Delete")) {
                        viewModel.delete(item: item)
                    },
                    secondaryButton: .cancel()
                )
            case .confirmBulkDelete:
                let count = viewModel.selectedURLs.count
                return Alert(
                    title: Text("Delete \(count) Selected Items?"),
                    message: Text("Are you sure you want to permanently delete these \(count) items?"),
                    primaryButton: .destructive(Text("Delete All")) {
                        viewModel.bulkDeleteSelected()
                    },
                    secondaryButton: .cancel()
                )
            case .rename(let item):
                return Alert(
                    title: Text("Rename “\(item.name)”"),
                    message: Text("Enter a new name for this item:"),
                    primaryButton: .default(Text("Rename")) {
                        viewModel.rename(item: item, to: viewModel.renameInput)
                    },
                    secondaryButton: .cancel()
                )
            case .error(let message):
                return Alert(
                    title: Text("Storage Explorer Error"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

// MARK: - Item Row Component

private struct ItemRow: View {
    let item: StorageExplorerItem
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .imageScale(.large)
            }
            
            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.url))
                .font(.title2)
                .foregroundColor(item.isDirectory ? .blue : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if item.isDirectory {
                        Text("\(item.itemCount) items")
                        Text("•")
                        Text(item.formattedSize)
                    } else {
                        Text(item.formattedSize)
                        Text("•")
                        Text(item.formattedDate)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if item.isDirectory && !isSelectionMode {
                NavigationLink(destination: DirectoryExplorerView(url: item.url)) {
                    EmptyView()
                }
                .frame(width: 0)
                .opacity(0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "ipa", "zip", "tar", "gz", "7z", "rar", "deb": return "doc.zipper"
        case "png", "jpg", "jpeg", "heic", "gif", "svg", "webp": return "photo"
        case "mp4", "mov", "m4v", "avi": return "film"
        case "mp3", "m4a", "wav", "aac", "flac": return "music.note"
        case "plist", "json", "xml", "txt", "log", "yaml", "yml": return "doc.text"
        case "dylib", "so", "dll", "exe", "bin", "a", "sys", "framework", "bundle": return "gearshape.2"
        case "db", "sqlite", "sqlite3", "storedata": return "cylinder.split.1x2"
        case "p12", "pem", "cer", "crt", "key", "mobileprovision", "provisionprofile": return "lock.doc"
        case "swift", "c", "cpp", "h", "m", "mm", "js", "ts", "py", "sh": return "chevron.left.forwardslash.chevron.right"
        case "pdf", "doc", "docx": return "doc.richtext"
        default: return "doc"
        }
    }
}

// MARK: - Root Storage Explorer View

public struct StorageExplorerView: View {
    @State private var locations: [StorageLocation] = []
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("App Storage Containers")) {
                    ForEach(locations) { location in
                        NavigationLink(destination: DirectoryExplorerView(url: location.url)) {
                            HStack(spacing: 12) {
                                Image(systemName: location.iconName)
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                        .font(.headline)
                                    Text(location.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Storage Explorer")
            .onAppear {
                self.loadLocations()
            }
        }
    }
    
    private func loadLocations() {
        var locs: [StorageLocation] = []
        let fileManager = FileManager.default
        
        // 1. Private Documents
        if let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            locs.append(StorageLocation(
                name: "Private Documents",
                subtitle: docsURL.path,
                iconName: "folder.badge.gearshape",
                url: docsURL
            ))
        }
        
        // 2. App Group Containers
        var seenGroupPaths = Set<String>()
        for groupID in Bundle.main.appGroups {
            if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID),
               !seenGroupPaths.contains(groupURL.path) {
                seenGroupPaths.insert(groupURL.path)
                locs.append(StorageLocation(
                    name: "App Group Container (\(groupID))",
                    subtitle: groupURL.path,
                    iconName: "shippingbox",
                    url: groupURL
                ))
            }
        }
        
        // 3. App Backups Directory
        if let backupsURL = fileManager.appBackupsDirectory {
            locs.append(StorageLocation(
                name: "App Backups Directory",
                subtitle: backupsURL.path,
                iconName: "archivebox",
                url: backupsURL
            ))
        }
        
        // 4. Temporary Directory
        let tmpURL = fileManager.temporaryDirectory
        locs.append(StorageLocation(
            name: "Temporary Directory (tmp)",
            subtitle: tmpURL.path,
            iconName: "trash.circle",
            url: tmpURL
        ))
        
        self.locations = locs
    }
}

// MARK: - UIActivityViewController Wrapper

private struct ShareItem: Identifiable {
    var id: String { url.path }
    let url: URL
}
