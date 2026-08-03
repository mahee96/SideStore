//
//  StorageExplorerView.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - Root Storage Explorer View

public struct StorageExplorerView: View {
    private static var cachedAppStorageUsed: String = ""
    private static var cachedFreeSpace: String = ""
    private static var cachedTotalSpace: String = ""
    
    @State private var locations: [StorageLocation] = []
    @State private var totalHardwareSpaceString: String = StorageExplorerView.cachedTotalSpace
    @State private var freeHardwareSpaceString: String = StorageExplorerView.cachedFreeSpace
    @State private var appStorageUsedString: String = StorageExplorerView.cachedAppStorageUsed
    @State private var statsTask: Task<Void, Never>? = nil
    
    public var onSelectFolder: ((URL) -> Void)?
    
    public init(onSelectFolder: ((URL) -> Void)? = nil) {
        self.onSelectFolder = onSelectFolder
    }
    
    public var body: some View {
        List {
            Section(
                header: Text("App Storage Containers"),
                footer: StorageExplorerFooterView(
                    appStorageUsedString: appStorageUsedString.isEmpty ? "Calculating..." : appStorageUsedString,
                    freeHardwareSpaceString: freeHardwareSpaceString,
                    totalHardwareSpaceString: totalHardwareSpaceString
                )
            ) {
                ForEach(locations) { location in
                    StorageLocationRowView(location: location, onSelectFolder: onSelectFolder)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Storage Explorer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            verboseLog("[StorageExplorerView] onAppear triggered")
            self.loadLocations()
            self.loadStorageStats()
        }
        .onDisappear {
            verboseLog("[StorageExplorerView] onDisappear triggered - cancelling statsTask")
            self.statsTask?.cancel()
            self.statsTask = nil
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
        verboseLog("[StorageExplorerView] loadStorageStats requested")
        statsTask?.cancel()
        
        statsTask = Task.detached {
            verboseLog("[StorageExplorerView] statsTask starting on background thread")
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
                if Task.isCancelled {
                    verboseLog("[StorageExplorerView] statsTask cancelled during container scan loop")
                    return
                }
                if !seenPaths.contains(containerURL.path) {
                    seenPaths.insert(containerURL.path)
                    let start = Date()
                    let size = StorageExplorerViewModel.calculateDirectorySize(url: containerURL)
                    let duration = Date().timeIntervalSince(start)
                    verboseLog("[StorageExplorerView] Scanned container: \(containerURL.path) -> Size: \(size) bytes (\(String(format: "%.3f", duration))s)")
                    totalAppSize += size
                }
            }
            
            if Task.isCancelled {
                verboseLog("[StorageExplorerView] statsTask cancelled before HW space query")
                return
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
            verboseLog("[StorageExplorerView] statsTask completed successfully. totalAppSize: \(appSizeStr), freeSpace: \(hwFreeStr)")
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                StorageExplorerView.cachedTotalSpace = hwTotalStr
                StorageExplorerView.cachedFreeSpace = hwFreeStr
                StorageExplorerView.cachedAppStorageUsed = appSizeStr
                
                self.totalHardwareSpaceString = hwTotalStr
                self.freeHardwareSpaceString = hwFreeStr
                self.appStorageUsedString = appSizeStr
            }
        }
    }
}

private struct StorageLocationRowView: View {
    let location: StorageLocation
    let onSelectFolder: ((URL) -> Void)?
    
    var body: some View {
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
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.secondary.opacity(0.4))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            verboseLog("[StorageLocationRowView] Tapped container location: \(location.name) (\(location.url.path))")
            onSelectFolder?(location.url)
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
