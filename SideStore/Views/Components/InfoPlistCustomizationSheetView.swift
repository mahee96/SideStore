//
//  InfoPlistCustomizationSheetView.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UIKit

public struct InfoPlistCustomizationSheetView: View {
    public let initialPlist: [String: Any]
    public let initialBundleID: String
    public let installedAppIdentities: [String: String]
    public let teamID: String
    public let onProceed: ([String: Any], Bool) -> Void
    public let onCancel: () -> Void

    @State private var bundleID: String
    @State private var previousValidBundleID: String
    @State private var appendTeamID: Bool
    @State private var displayName: String
    @State private var versionString: String
    @State private var buildNumber: String
    @State private var minimumOSVersion: String
    @State private var fileSharingEnabled: Bool
    @State private var openingDocumentsInPlace: Bool

    @State private var rawEntries: [RawPlistEntry] = []
    @State private var rawSearchQuery: String = ""
    @State private var isShowingRawKeys: Bool = false
    @State private var isShowingAddKeySheet: Bool = false
    @State private var newKeyName: String = ""
    @State private var newKeyValue: String = ""
    @State private var newKeyType: RawPlistType = .string

    public enum RawPlistType: String, CaseIterable, Identifiable {
        case string = "String"
        case boolean = "Boolean"
        case number = "Number"

        public var id: String { rawValue }
    }

    public struct RawPlistEntry: Identifiable {
        public let id = UUID()
        public var key: String
        public var value: String
        public var type: RawPlistType
    }

    public init(
        initialPlist: [String: Any],
        initialBundleID: String,
        appendTeamID: Bool = true,
        installedAppIdentities: [String: String] = [:],
        teamID: String = "",
        onProceed: @escaping ([String: Any], Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialPlist = initialPlist
        self.initialBundleID = initialBundleID
        self.installedAppIdentities = installedAppIdentities
        self.teamID = teamID
        self.onProceed = onProceed
        self.onCancel = onCancel

        let initialName = (initialPlist["CFBundleDisplayName"] as? String)
            ?? (initialPlist["CFBundleName"] as? String)
            ?? ""
        let initialVersion = (initialPlist["CFBundleShortVersionString"] as? String) ?? ""
        let initialBuild = (initialPlist["CFBundleVersion"] as? String) ?? ""
        let initialMinOS = (initialPlist["MinimumOSVersion"] as? String) ?? ""
        let initialFileSharing = (initialPlist["UIFileSharingEnabled"] as? Bool) ?? false
        let initialDocInPlace = (initialPlist["LSSupportsOpeningDocumentsInPlace"] as? Bool) ?? false

        let startingBundleID: String = {
            let trimmed = initialBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let base: String
            if !teamID.isEmpty && trimmed.hasSuffix(".\(teamID)") {
                base = String(trimmed.dropLast((".\(teamID)").count))
            } else {
                base = trimmed
            }
            let sanitizedBase = InfoPlistParser.sanitizeBundleID(base)
            if appendTeamID && !teamID.isEmpty {
                return "\(sanitizedBase).\(teamID)"
            }
            return sanitizedBase
        }()

        _bundleID = State(initialValue: startingBundleID)
        _previousValidBundleID = State(initialValue: startingBundleID)
        _appendTeamID = State(initialValue: appendTeamID)
        _displayName = State(initialValue: initialName)
        _versionString = State(initialValue: initialVersion)
        _buildNumber = State(initialValue: initialBuild)
        _minimumOSVersion = State(initialValue: initialMinOS)
        _fileSharingEnabled = State(initialValue: initialFileSharing)
        _openingDocumentsInPlace = State(initialValue: initialDocInPlace)

        let standardKeys: Set<String> = [
            "CFBundleIdentifier",
            "CFBundleDisplayName",
            "CFBundleName",
            "CFBundleShortVersionString",
            "CFBundleVersion",
            "MinimumOSVersion",
            "UIFileSharingEnabled",
            "LSSupportsOpeningDocumentsInPlace"
        ]

        var entries: [RawPlistEntry] = []
        for (key, val) in initialPlist where !standardKeys.contains(key) {
            if let boolVal = val as? Bool {
                entries.append(RawPlistEntry(key: key, value: boolVal ? "YES" : "NO", type: .boolean))
            } else if let numVal = val as? NSNumber {
                entries.append(RawPlistEntry(key: key, value: numVal.stringValue, type: .number))
            } else if let strVal = val as? String {
                entries.append(RawPlistEntry(key: key, value: strVal, type: .string))
            }
        }
        entries.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        _rawEntries = State(initialValue: entries)
    }
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identitySection
                    versionSection
                    capabilitiesSection
                    advancedKeysSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    hideKeyboard()
                }
            )
            .navigationTitle("Customize Info.plist")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: SwiftUI.Button("Cancel") {
                    onCancel()
                },
                trailing: SwiftUI.Button("Proceed") {
                    handleProceed()
                }
                .font(.system(size: 16, weight: .bold))
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    SwiftUI.Button("Done") {
                        hideKeyboard()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $isShowingAddKeySheet) {
            addKeySheet
        }
    }

    private var resolvedEffectiveBundleID: String {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        if appendTeamID && !teamID.isEmpty {
            if trimmed.hasSuffix(".\(teamID)") {
                return trimmed
            } else {
                return "\(trimmed).\(teamID)"
            }
        }
        return trimmed
    }

    private var matchingExistingAppName: String? {
        let target = resolvedEffectiveBundleID
        return installedAppIdentities[target]
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "APP IDENTITY", icon: "app.badge.checkmark")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bundle Identifier")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SuffixEnforcedTextField(
                        text: $bundleID,
                        placeholder: "com.example.app",
                        suffix: !teamID.isEmpty ? ".\(teamID)" : "",
                        isSuffixEnforced: appendTeamID,
                        autocapitalization: .none,
                        onCommit: { hideKeyboard() }
                    )
                    .frame(height: 22)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().padding(.leading, 16)

                SwiftUI.Button(action: {
                    appendTeamID.toggle()
                    guard !teamID.isEmpty else { return }
                    let suffix = ".\(teamID)"
                    if appendTeamID {
                        let clean = InfoPlistParser.sanitizeBundleID(bundleID)
                        bundleID = clean.hasSuffix(suffix) ? clean : "\(clean)\(suffix)"
                    } else {
                        if bundleID.hasSuffix(suffix) {
                            bundleID = String(bundleID.dropLast(suffix.count))
                        }
                    }
                    previousValidBundleID = bundleID
                }) {
                    HStack {
                        Text("Append Team ID to Bundle Identifier")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: appendTeamID ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(appendTeamID ? .blue : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("My App", text: $displayName)
                        .font(.system(size: 15))
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let existingName = matchingExistingAppName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                    Text("Matches installed app \"\(existingName)\" — will update existing app")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            } else {
                Text("If the bundle ID is not present in the database, it will install as a separate app.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "VERSIONING", icon: "number")

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("1.0.0", text: $versionString)
                            .font(.system(size: 15))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .onSubmit { hideKeyboard() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider().frame(height: 38)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Build")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("1", text: $buildNumber)
                            .font(.system(size: 15))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .onSubmit { hideKeyboard() }
                    }
                    .frame(width: 90)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider().padding(.leading, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum iOS Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("15.0", text: $minimumOSVersion)
                        .font(.system(size: 15))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "CAPABILITIES & SHARING", icon: "folder.badge.gearshape")

            VStack(spacing: 0) {
                Toggle(isOn: $fileSharingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable iTunes File Sharing")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                        Text("Exposes Documents directory via Finder/iTunes")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider().padding(.leading, 16)

                Toggle(isOn: $openingDocumentsInPlace) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Documents In Place")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                        Text("Allows Files app to edit documents directly")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var advancedKeysSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader(title: "ALL RAW KEYS", icon: "ellipsis.curlybraces")
                Spacer()
                SwiftUI.Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingRawKeys.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isShowingRawKeys ? "Collapse" : "Expand (\(rawEntries.count))")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: isShowingRawKeys ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                    .padding(.trailing, 16)
                }
            }

            if isShowingRawKeys {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            TextField("Filter keys...", text: $rawSearchQuery)
                                .font(.system(size: 14))
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                            if !rawSearchQuery.isEmpty {
                                SwiftUI.Button(action: { rawSearchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        SwiftUI.Button(action: { isShowingAddKeySheet = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(12)

                    let filtered = rawEntries.filter {
                        rawSearchQuery.isEmpty || $0.key.localizedCaseInsensitiveContains(rawSearchQuery)
                    }

                    if filtered.isEmpty {
                        Divider().padding(.leading, 16)
                        Text("No matching keys found")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(filtered.indices, id: \.self) { index in
                            Divider().padding(.leading, 16)
                            let item = filtered[index]
                            rawKeyRow(for: item)
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func rawKeyRow(for item: RawPlistEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.key)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text(item.type.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())

                SwiftUI.Button(action: {
                    rawEntries.removeAll { $0.key == item.key }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            if let targetIdx = rawEntries.firstIndex(where: { $0.key == item.key }) {
                if item.type == .boolean {
                    Picker("", selection: Binding(
                        get: { rawEntries[targetIdx].value == "YES" },
                        set: { rawEntries[targetIdx].value = $0 ? "YES" : "NO" }
                    )) {
                        Text("YES").tag(true)
                        Text("NO").tag(false)
                    }
                    .pickerStyle(.segmented)
                } else {
                    TextField("Value", text: $rawEntries[targetIdx].value)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var addKeySheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Key Name")) {
                    TextField("e.g. CFBundleURLTypes", text: $newKeyName)
                        .autocapitalization(.none)
                }

                Section(header: Text("Value Type")) {
                    Picker("Type", selection: $newKeyType) {
                        ForEach(RawPlistType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Value")) {
                    if newKeyType == .boolean {
                        Picker("Boolean Value", selection: $newKeyValue) {
                            Text("YES").tag("YES")
                            Text("NO").tag("NO")
                        }
                        .pickerStyle(.segmented)
                    } else {
                        TextField("Value", text: $newKeyValue)
                            .autocapitalization(.none)
                    }
                }
            }
            .navigationTitle("Add Plist Key")
            .navigationBarItems(
                leading: SwiftUI.Button("Cancel") {
                    newKeyName = ""
                    newKeyValue = ""
                    isShowingAddKeySheet = false
                },
                trailing: SwiftUI.Button("Add") {
                    let trimmed = newKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    rawEntries.removeAll { $0.key == trimmed }
                    let finalVal = newKeyType == .boolean && newKeyValue.isEmpty ? "YES" : newKeyValue
                    rawEntries.append(RawPlistEntry(key: trimmed, value: finalVal, type: newKeyType))
                    newKeyName = ""
                    newKeyValue = ""
                    isShowingAddKeySheet = false
                }
                .disabled(newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.secondary)
        .padding(.leading, 4)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func handleProceed() {
        var updated = initialPlist

        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBaseID: String = {
            let suffix = ".\(teamID)"
            let base: String
            if appendTeamID && !teamID.isEmpty && trimmed.hasSuffix(suffix) {
                base = String(trimmed.dropLast(suffix.count))
            } else {
                base = trimmed
            }
            return InfoPlistParser.sanitizeBundleID(base)
        }()
        if !cleanBaseID.isEmpty {
            updated["CFBundleIdentifier"] = cleanBaseID
        }

        let cleanDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanDisplayName.isEmpty {
            updated["CFBundleDisplayName"] = cleanDisplayName
            updated["CFBundleName"] = cleanDisplayName
        }

        let cleanVersion = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanVersion.isEmpty {
            updated["CFBundleShortVersionString"] = cleanVersion
        }

        let cleanBuild = buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanBuild.isEmpty {
            updated["CFBundleVersion"] = cleanBuild
        }

        let cleanMinOS = minimumOSVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanMinOS.isEmpty {
            updated["MinimumOSVersion"] = cleanMinOS
        }

        updated["UIFileSharingEnabled"] = fileSharingEnabled
        updated["LSSupportsOpeningDocumentsInPlace"] = openingDocumentsInPlace

        for entry in rawEntries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            switch entry.type {
            case .boolean:
                updated[key] = (entry.value.uppercased() == "YES" || entry.value == "1" || entry.value.lowercased() == "true")
            case .number:
                if let intVal = Int(entry.value) {
                    updated[key] = intVal
                } else if let doubleVal = Double(entry.value) {
                    updated[key] = doubleVal
                } else {
                    updated[key] = entry.value
                }
            case .string:
                updated[key] = entry.value
            }
        }

        onProceed(updated, appendTeamID)
    }
}

private final class SheetDismissDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
    private var isResumed = false
    var onDismiss: (() -> Void)?

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        resumeOnce()
    }

    func resumeOnce() {
        guard !isResumed else { return }
        isResumed = true
        onDismiss?()
    }
}

private final class SheetHostingController<Content: View>: UIHostingController<Content> {
    var dismissDelegate: UIAdaptivePresentationControllerDelegate?
}

extension InfoPlistCustomizationSheetView {
    @MainActor
    public static func present(
        from presenter: UIViewController,
        initialPlist: [String: Any],
        initialBundleID: String,
        appendTeamID: Bool = true,
        installedAppIdentities: [String: String] = [:],
        teamID: String = ""
    ) async -> (modifiedPlist: [String: Any], appendTeamID: Bool)? {
        await withCheckedContinuation { continuation in
            var hostingController: SheetHostingController<AnyView>?
            let dismissDelegate = SheetDismissDelegate()

            var hasResumed = false
            let safeResume: ((modifiedPlist: [String: Any], appendTeamID: Bool)?) -> Void = { result in
                guard !hasResumed else { return }
                hasResumed = true
                dismissDelegate.resumeOnce()
                continuation.resume(returning: result)
            }

            dismissDelegate.onDismiss = {
                safeResume(nil)
            }

            let view = InfoPlistCustomizationSheetView(
                initialPlist: initialPlist,
                initialBundleID: initialBundleID,
                appendTeamID: appendTeamID,
                installedAppIdentities: installedAppIdentities,
                teamID: teamID,
                onProceed: { modifiedPlist, shouldAppend in
                    hostingController?.dismiss(animated: true) {
                        safeResume((modifiedPlist, shouldAppend))
                    }
                },
                onCancel: {
                    hostingController?.dismiss(animated: true) {
                        safeResume(nil)
                    }
                }
            )

            let controller = SheetHostingController(rootView: AnyView(view))
            controller.dismissDelegate = dismissDelegate
            controller.modalPresentationStyle = .pageSheet
            controller.presentationController?.delegate = dismissDelegate
            if #available(iOS 15.0, *) {
                if let sheet = controller.sheetPresentationController {
                    sheet.detents = [.large()]
                    sheet.prefersGrabberVisible = true
                }
            }
            hostingController = controller

            presenter.present(controller, animated: true)
        }
    }
}
