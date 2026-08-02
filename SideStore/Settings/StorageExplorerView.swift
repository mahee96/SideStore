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
    
    @Published public var copiedURLs: [URL] = []
    
    private init() {}
    
    public var hasCopiedItems: Bool {
        !copiedURLs.isEmpty
    }
    
    public var pasteLabelText: String {
        if copiedURLs.count == 1, let first = copiedURLs.first {
            return "Paste “\(first.lastPathComponent)”"
        } else if copiedURLs.count > 1 {
            return "Paste \(copiedURLs.count) Items"
        }
        return "Paste"
    }
    
    public func setCopied(urls: [URL]) {
        self.copiedURLs = urls
    }
    
    public func clear() {
        self.copiedURLs.removeAll()
    }
}

// MARK: - Paste Conflict Model

public struct PasteConflict: Identifiable {
    public var id: String { sourceURL.path }
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let existingName: String
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
    @Published public var isTextWrapEnabled: Bool = false
    @Published public var isLoading: Bool = false
    
    @Published public var isSelectionMode: Bool = false
    @Published public var selectedURLs: Set<URL> = []
    
    @Published public var currentFolderSize: Int64 = 0
    @Published public var freeDiskSpaceString: String = ""
    
    @Published public var activeAlert: ActiveAlert? = nil
    @Published public var itemToRename: StorageExplorerItem? = nil
    @Published public var renameInput: String = ""
    @Published public var shareURL: URL? = nil
    
    @Published public var pendingConflicts: [PasteConflict] = []
    @Published public var currentConflict: PasteConflict? = nil
    @Published public var conflictNewNameInput: String = ""
    
    public enum ActiveAlert: Identifiable {
        case confirmSingleDelete(StorageExplorerItem)
        case confirmBulkDelete
        case rename(StorageExplorerItem)
        case bulkRename
        case pasteConflict(PasteConflict)
        case error(String)
        
        public var id: String {
            switch self {
            case .confirmSingleDelete(let item): return "singleDelete-\(item.url.path)"
            case .confirmBulkDelete: return "bulkDelete"
            case .rename(let item): return "rename-\(item.url.path)"
            case .bulkRename: return "bulkRename"
            case .pasteConflict(let c): return "conflict-\(c.sourceURL.path)"
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
    
    public static func calculateDirectorySize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        var total: Int64 = 0
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = vals.fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
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
                        size = await Self.calculateDirectorySize(url: itemURL)
                        if let subContents = try? fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                            itemCount = subContents.count
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
    
    public func bulkRenameSelected(to newBaseName: String) {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let targets = items.filter { selectedURLs.contains($0.url) }
        guard !targets.isEmpty else { return }
        
        if targets.count == 1, let item = targets.first {
            rename(item: item, to: trimmed)
            self.selectedURLs.removeAll()
            self.isSelectionMode = false
            return
        }
        
        var errors: [String] = []
        var index = 1
        
        for item in targets {
            let ext = item.url.pathExtension
            let nameWithoutExt = ext.isEmpty ? "\(trimmed)_\(index)" : "\(trimmed)_\(index).\(ext)"
            let destinationURL = item.url.deletingLastPathComponent().appendingPathComponent(nameWithoutExt)
            
            do {
                try FileManager.default.moveItem(at: item.url, to: destinationURL)
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
            index += 1
        }
        
        self.selectedURLs.removeAll()
        self.isSelectionMode = false
        self.loadContents()
        
        if !errors.isEmpty {
            self.activeAlert = .error("Errors renaming items:\n" + errors.joined(separator: "\n"))
        }
    }
    
    public func copyToClipboard(item: StorageExplorerItem) {
        StorageExplorerClipboard.shared.setCopied(urls: [item.url])
    }
    
    public func copySelectedToClipboard() {
        let selected = items.filter { selectedURLs.contains($0.url) }.map { $0.url }
        if !selected.isEmpty {
            StorageExplorerClipboard.shared.setCopied(urls: selected)
            self.isSelectionMode = false
            self.selectedURLs.removeAll()
        }
    }
    
    public func pasteCopiedItems() {
        let sources = StorageExplorerClipboard.shared.copiedURLs
        guard !sources.isEmpty else { return }
        
        var conflicts: [PasteConflict] = []
        var copyErrors: [String] = []
        let fileManager = FileManager.default
        
        // Phase 1: Complete all non-conflicting items immediately (including recursive directories)
        for sourceURL in sources {
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let destURL = self.currentURL.appendingPathComponent(sourceURL.lastPathComponent)
            
            if fileManager.fileExists(atPath: destURL.path) {
                conflicts.append(PasteConflict(sourceURL: sourceURL, destinationDirectory: self.currentURL, existingName: sourceURL.lastPathComponent))
            } else {
                do {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                } catch {
                    copyErrors.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        
        self.loadContents()
        
        // Phase 2: Process conflicts sequentially
        if !conflicts.isEmpty {
            self.pendingConflicts = conflicts
            self.presentNextConflict()
        } else if !copyErrors.isEmpty {
            self.activeAlert = .error("Errors copying items:\n" + copyErrors.joined(separator: "\n"))
        }
    }
    
    private func presentNextConflict() {
        guard let next = pendingConflicts.first else {
            self.currentConflict = nil
            self.loadContents()
            return
        }
        self.currentConflict = next
        self.conflictNewNameInput = next.existingName
        self.activeAlert = .pasteConflict(next)
    }
    
    public func resolveConflictWithNewName() {
        guard let conflict = currentConflict else { return }
        let trimmed = conflictNewNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else { return }
        
        let destURL = conflict.destinationDirectory.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: destURL.path) {
            // Name still conflicts!
            self.activeAlert = .error("A file named “\(trimmed)” already exists in this folder. Please choose a different name.")
            return
        }
        
        do {
            try FileManager.default.copyItem(at: conflict.sourceURL, to: destURL)
        } catch {
            debugLog("Error copying conflict item: \(error)")
        }
        
        if !pendingConflicts.isEmpty {
            pendingConflicts.removeFirst()
        }
        self.presentNextConflict()
    }
    
    public func cancelRemainingConflicts() {
        self.pendingConflicts.removeAll()
        self.currentConflict = nil
        self.loadContents()
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
        let items = viewModel.filteredAndSortedItems
        if items.isEmpty {
            return "0 items (Zero KB)"
        }
        let folders = items.filter { $0.isDirectory }
        let files = items.filter { !$0.isDirectory }
        let sizeStr = ByteCountFormatter.string(fromByteCount: viewModel.currentFolderSize, countStyle: .file)
        
        if !folders.isEmpty && !files.isEmpty {
            let folderLabel = folders.count == 1 ? "1 Folder" : "\(folders.count) Folders"
            let fileLabel = files.count == 1 ? "1 File" : "\(files.count) Files"
            return "\(folderLabel), \(fileLabel) (\(sizeStr))"
        } else if !folders.isEmpty {
            let folderLabel = folders.count == 1 ? "1 Folder" : "\(folders.count) Folders"
            return "\(folderLabel) (\(sizeStr))"
        } else {
            let fileLabel = files.count == 1 ? "1 File" : "\(files.count) Files"
            return "\(fileLabel) (\(sizeStr))"
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.filteredAndSortedItems.isEmpty {
                Spacer()
                
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.minus")
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    VStack(spacing: 4) {
                        Text("Empty Directory")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.primary)
                        
                        Text("No files or subfolders found in this directory.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .contextMenu {
                    EmptyAreaContextMenuView(viewModel: viewModel, clipboard: clipboard)
                }
                
                Spacer()
            } else {
                List {
                    DirectoryItemListSectionView(viewModel: viewModel, clipboard: clipboard)
                    EmptyPasteAreaSectionView(viewModel: viewModel, clipboard: clipboard)
                }
                .listStyle(.insetGrouped)
                .searchable(text: $viewModel.searchText, prompt: "Search files & folders")
            }
            
            // Bottom Status & Storage Information Bar + Selection Actions Bar
            VStack(spacing: 0) {
                Divider()
                
                if viewModel.isSelectionMode {
                    SelectionActionBarView(viewModel: viewModel)
                    Divider()
                }
                
                BottomInformationBarView(viewModel: viewModel, clipboard: clipboard, folderSummaryString: folderSummaryString)
            }
        }
        .navigationTitle(viewModel.currentURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                TrailingToolbarMenuView(viewModel: viewModel)
            }
        }
        .sheet(item: Binding(get: {
            viewModel.shareURL.map { ShareItem(url: $0) }
        }, set: { newValue in
            viewModel.shareURL = newValue?.url
        })) { shareItem in
            ActivityViewController(activityItems: [shareItem.url])
        }
        .alert(item: $viewModel.activeAlert, content: makeAlert)
    }
    
    private func makeAlert(for alertType: StorageExplorerViewModel.ActiveAlert) -> Alert {
        let vm = self.viewModel
        switch alertType {
        case .confirmSingleDelete(let item):
            return Alert(
                title: Text("Delete “\(item.name)”?"),
                message: Text("This item will be permanently removed."),
                primaryButton: .destructive(Text("Delete")) {
                    vm.delete(item: item)
                },
                secondaryButton: .cancel()
            )
        case .confirmBulkDelete:
            let count = vm.selectedURLs.count
            return Alert(
                title: Text("Delete \(count) Selected Items?"),
                message: Text("Are you sure you want to permanently delete these \(count) items?"),
                primaryButton: .destructive(Text("Delete All")) {
                    vm.bulkDeleteSelected()
                },
                secondaryButton: .cancel()
            )
        case .rename(let item):
            return Alert(
                title: Text("Rename “\(item.name)”"),
                message: Text("Enter a new name for this item:"),
                primaryButton: .default(Text("Rename")) {
                    vm.rename(item: item, to: vm.renameInput)
                },
                secondaryButton: .cancel()
            )
        case .bulkRename:
            let count = vm.selectedURLs.count
            let input = vm.renameInput
            return Alert(
                title: Text(count == 1 ? "Rename Item" : "Bulk Rename \(count) Items"),
                message: Text(count == 1 ? "Enter a new name:" : "Enter a base name (items will be renamed Name_1, Name_2...):"),
                primaryButton: .default(Text("Rename")) {
                    vm.bulkRenameSelected(to: input)
                },
                secondaryButton: .cancel()
            )
        case .pasteConflict(let conflict):
            return Alert(
                title: Text("File Already Exists"),
                message: Text("An item named “\(conflict.existingName)” already exists in this folder. Enter a new name to copy:"),
                primaryButton: .default(Text("Copy as New Name")) {
                    vm.resolveConflictWithNewName()
                },
                secondaryButton: .cancel(Text("Cancel All")) {
                    vm.cancelRemainingConflicts()
                }
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

// MARK: - Subview Components

private struct DirectoryItemListSectionView: View {
    @ObservedObject var viewModel: StorageExplorerViewModel
    @ObservedObject var clipboard: StorageExplorerClipboard
    
    var body: some View {
        let items = viewModel.filteredAndSortedItems
        let folders = items.filter { $0.isDirectory }
        let files = items.filter { !$0.isDirectory }
        
        if !folders.isEmpty && !files.isEmpty {
            Section("Folders (\(folders.count))") {
                ForEach(folders) { item in
                    renderRow(item: item)
                }
            }
            
            Section("Files (\(files.count))") {
                ForEach(files) { item in
                    renderRow(item: item)
                }
            }
        } else if !folders.isEmpty {
            Section("Folders (\(folders.count))") {
                ForEach(folders) { item in
                    renderRow(item: item)
                }
            }
        } else {
            Section("Files (\(files.count))") {
                ForEach(files) { item in
                    renderRow(item: item)
                }
            }
        }
    }
    
    @ViewBuilder
    private func renderRow(item: StorageExplorerItem) -> some View {
        if viewModel.isSelectionMode {
            ItemRow(item: item, isSelected: viewModel.selectedURLs.contains(item.url), isSelectionMode: true, isTextWrapEnabled: viewModel.isTextWrapEnabled)
                .onTapGesture {
                    if viewModel.selectedURLs.contains(item.url) {
                        viewModel.selectedURLs.remove(item.url)
                    } else {
                        viewModel.selectedURLs.insert(item.url)
                    }
                }
        } else if item.isDirectory {
            NavigationLink(destination: DirectoryExplorerView(url: item.url)) {
                ItemRow(item: item, isSelected: false, isSelectionMode: false, isTextWrapEnabled: viewModel.isTextWrapEnabled)
            }
            .contextMenu {
                ItemContextMenuView(viewModel: viewModel, item: item)
            }
        } else {
            ItemRow(item: item, isSelected: false, isSelectionMode: false, isTextWrapEnabled: viewModel.isTextWrapEnabled)
                .contextMenu {
                    ItemContextMenuView(viewModel: viewModel, item: item)
                }
        }
    }
}

private struct EmptyPasteAreaSectionView: View {
    @ObservedObject var viewModel: StorageExplorerViewModel
    @ObservedObject var clipboard: StorageExplorerClipboard
    
    var body: some View {
        Section {
            Color.clear
                .frame(height: 100)
                .listRowBackground(Color.clear)
                .contextMenu {
                    EmptyAreaContextMenuView(viewModel: viewModel, clipboard: clipboard)
                }
        }
    }
}

private struct SelectionActionBarView: View {
    @ObservedObject var viewModel: StorageExplorerViewModel
    
    var body: some View {
        let count = viewModel.selectedURLs.count
        let copyTitle = count > 0 ? "Copy (\(count))" : "Copy"
        let renameTitle = count > 0 ? "Rename (\(count))" : "Rename"
        let deleteTitle = count > 0 ? "Delete (\(count))" : "Delete"
        let isAllSelected = count > 0 && count == viewModel.filteredAndSortedItems.count
        let selectTitle = isAllSelected ? "Deselect All" : "Select All"
        
        HStack(spacing: 6) {
            SwiftUI.Button {
                if isAllSelected {
                    viewModel.selectedURLs.removeAll()
                } else {
                    viewModel.selectedURLs = Set(viewModel.filteredAndSortedItems.map { $0.url })
                }
            } label: {
                Text(selectTitle)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            
            Spacer(minLength: 2)
            
            SwiftUI.Button {
                if !viewModel.selectedURLs.isEmpty {
                    viewModel.copySelectedToClipboard()
                }
            } label: {
                Label(copyTitle, systemImage: "doc.on.doc")
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.selectedURLs.isEmpty)
            
            SwiftUI.Button {
                if !viewModel.selectedURLs.isEmpty {
                    if count == 1, let firstURL = viewModel.selectedURLs.first, let item = viewModel.items.first(where: { $0.url == firstURL }) {
                        viewModel.renameInput = item.name
                    } else {
                        viewModel.renameInput = ""
                    }
                    viewModel.activeAlert = .bulkRename
                }
            } label: {
                Label(renameTitle, systemImage: "pencil")
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.selectedURLs.isEmpty)
            
            SwiftUI.Button(role: .destructive) {
                if !viewModel.selectedURLs.isEmpty {
                    viewModel.activeAlert = .confirmBulkDelete
                }
            } label: {
                Label(deleteTitle, systemImage: "trash")
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.selectedURLs.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(UIColor.tertiarySystemBackground))
    }
}

private struct BottomInformationBarView: View {
    @ObservedObject var viewModel: StorageExplorerViewModel
    @ObservedObject var clipboard: StorageExplorerClipboard
    let folderSummaryString: String
    
    var body: some View {
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
            
            if clipboard.hasCopiedItems && !viewModel.isSelectionMode {
                SwiftUI.Button {
                    viewModel.pasteCopiedItems()
                } label: {
                    Label(clipboard.pasteLabelText, systemImage: "doc.on.clipboard")
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

private struct TrailingToolbarMenuView: View {
    @ObservedObject var viewModel: StorageExplorerViewModel
    
    var body: some View {
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
                Label("Folders First", systemImage: "folder")
            }
            
            Toggle(isOn: $viewModel.isTextWrapEnabled) {
                Label("Wrap File Names", systemImage: "text.wrap")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

private struct ItemContextMenuView: View {
    @ObservedObject var viewModel: StorageExplorerViewModel
    let item: StorageExplorerItem
    
    var body: some View {
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
}

private struct EmptyAreaContextMenuView: View {
    @ObservedObject var viewModel: StorageExplorerViewModel
    @ObservedObject var clipboard: StorageExplorerClipboard
    
    var body: some View {
        if clipboard.hasCopiedItems {
            SwiftUI.Button {
                viewModel.pasteCopiedItems()
            } label: {
                Label(clipboard.pasteLabelText, systemImage: "doc.on.clipboard")
            }
        }
    }
}

private struct StorageExplorerFooterView: View {
    let appStorageUsedString: String
    let freeHardwareSpaceString: String
    let totalHardwareSpaceString: String
    
    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            if !appStorageUsedString.isEmpty {
                HStack(spacing: 4) {
                    Text("App Storage Used:")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(appStorageUsedString)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            if !freeHardwareSpaceString.isEmpty {
                HStack(spacing: 4) {
                    Text("Available Space:")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(freeHardwareSpaceString)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            if !totalHardwareSpaceString.isEmpty {
                HStack(spacing: 4) {
                    Text("Total Space:")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(totalHardwareSpaceString)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Item Row Component

private struct ItemRow: View {
    let item: StorageExplorerItem
    let isSelected: Bool
    let isSelectionMode: Bool
    let isTextWrapEnabled: Bool
    
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
                if isTextWrapEnabled {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(1)
                }
                
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
        }
        .contentShape(Rectangle())
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
    @State private var totalHardwareSpaceString: String = ""
    @State private var freeHardwareSpaceString: String = ""
    @State private var appStorageUsedString: String = ""
    
    public init() {}
    
    public var body: some View {
        List {
            Section(
                header: Text("App Storage Containers"),
                footer: StorageExplorerFooterView(
                    appStorageUsedString: appStorageUsedString,
                    freeHardwareSpaceString: freeHardwareSpaceString,
                    totalHardwareSpaceString: totalHardwareSpaceString
                )
            ) {
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            self.loadLocations()
            self.loadStorageStats()
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
    
    private func loadStorageStats() {
        Task.detached {
            let fileManager = FileManager.default
            var totalAppSize: Int64 = 0
            
            var containerURLs: [URL] = []
            if let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                containerURLs.append(docsURL)
            }
            for groupID in Bundle.main.appGroups {
                if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
                    containerURLs.append(groupURL)
                }
            }
            if let backupsURL = fileManager.appBackupsDirectory {
                containerURLs.append(backupsURL)
            }
            containerURLs.append(fileManager.temporaryDirectory)
            
            var seenPaths = Set<String>()
            for containerURL in containerURLs {
                if !seenPaths.contains(containerURL.path) {
                    seenPaths.insert(containerURL.path)
                    totalAppSize += StorageExplorerViewModel.calculateDirectorySize(url: containerURL)
                }
            }
            
            var hwTotalStr = "Unknown"
            var hwFreeStr = "Unknown"
            do {
                let values = try fileManager.temporaryDirectory.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                if let total = values.volumeTotalCapacity {
                    hwTotalStr = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
                }
                if let free = values.volumeAvailableCapacityForImportantUsage {
                    hwFreeStr = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                } else if let free = values.volumeAvailableCapacity {
                    hwFreeStr = ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)
                }
            } catch {}
            
            let appSizeStr = ByteCountFormatter.string(fromByteCount: totalAppSize, countStyle: .file)
            
            await MainActor.run {
                self.totalHardwareSpaceString = hwTotalStr
                self.freeHardwareSpaceString = hwFreeStr
                self.appStorageUsedString = appSizeStr
            }
        }
    }
}

// MARK: - UIActivityViewController Wrapper

private struct ShareItem: Identifiable {
    var id: String { url.path }
    let url: URL
}
