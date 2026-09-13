//
//  EntitlementsCustomizationViewModel.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UIKit
import SideSign

public struct EntitlementEntry: Identifiable {
    public let id = UUID()
    public var key: String
    public var type: EntitlementValueType
    public var boolValue: Bool
    public var stringValue: String
    public var arrayValue: [String]
    public var isAppDefault: Bool

    public init(
        key: String,
        type: EntitlementValueType,
        boolValue: Bool = true,
        stringValue: String = "",
        arrayValue: [String] = [],
        isAppDefault: Bool = false
    ) {
        self.key = key
        self.type = type
        self.boolValue = boolValue
        self.stringValue = stringValue
        self.arrayValue = arrayValue
        self.isAppDefault = isAppDefault
    }
}

final class EntitlementsCustomizationViewModel: ObservableObject {
    let bundleID: String
    let teamType: ALTTeamType
    let onProceed: ([String: any Sendable]) -> Void
    let onCancel: () -> Void

    @Published var activeEntries: [EntitlementEntry] = []
    @Published var searchQuery: String = ""
    @Published var isShowingAddCustomSheet: Bool = false
    @Published var newCustomKey: String = ""
    @Published var newCustomType: EntitlementValueType = .boolean
    @Published var newCustomString: String = ""
    @Published var newCustomBool: Bool = true
    @Published var newCustomArrayText: String = ""
    @Published var newArrayItemText: String = ""

    init(
        initialEntitlements: [String: any Sendable],
        bundleID: String,
        teamType: ALTTeamType,
        onProceed: @escaping ([String: any Sendable]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.bundleID = bundleID
        self.teamType = teamType
        self.onProceed = onProceed
        self.onCancel = onCancel

        var entries: [EntitlementEntry] = []
        for (key, val) in initialEntitlements {
            if let boolVal = val as? Bool {
                entries.append(EntitlementEntry(key: key, type: .boolean, boolValue: boolVal, isAppDefault: true))
            } else if let arrVal = val as? [String] {
                entries.append(EntitlementEntry(key: key, type: .stringArray, arrayValue: arrVal, isAppDefault: true))
            } else if let strVal = val as? String {
                entries.append(EntitlementEntry(key: key, type: .string, stringValue: strVal, isAppDefault: true))
            } else if let numVal = val as? NSNumber {
                entries.append(EntitlementEntry(key: key, type: .number, stringValue: numVal.stringValue, isAppDefault: true))
            }
        }
        entries.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        self.activeEntries = entries
    }

    func isEntitlementAllowed(_ key: String) -> Bool {
        if teamType == .free {
            let allowed = teamType.allowedEntitlements ?? Entitlement.freeEntitlements
            return allowed.map(\.rawValue).contains(key)
        }
        return true
    }

    var filteredActiveEntries: [EntitlementEntry] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return activeEntries
        }
        return activeEntries.filter {
            $0.key.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    static var knownCatalog: [Entitlement] {
        Entitlement.allKnown
    }

    var availableCatalogEntries: [Entitlement] {
        let activeKeysSet = Set(activeEntries.map(\.key))
        return Entitlement.allKnown.filter { ent in
            !activeKeysSet.contains(ent.rawValue) &&
            isEntitlementAllowed(ent.rawValue) &&
            (searchQuery.isEmpty || ent.displayName.localizedCaseInsensitiveContains(searchQuery) || ent.rawValue.localizedCaseInsensitiveContains(searchQuery))
        }
    }

    func bindingForBool(entryID: UUID) -> Binding<Bool> {
        Binding<Bool>(
            get: { [weak self] in
                self?.activeEntries.first(where: { $0.id == entryID })?.boolValue ?? false
            },
            set: { [weak self] newVal in
                if let idx = self?.activeEntries.firstIndex(where: { $0.id == entryID }) {
                    self?.activeEntries[idx].boolValue = newVal
                }
            }
        )
    }

    func bindingForString(entryID: UUID) -> Binding<String> {
        Binding<String>(
            get: { [weak self] in
                self?.activeEntries.first(where: { $0.id == entryID })?.stringValue ?? ""
            },
            set: { [weak self] newVal in
                if let idx = self?.activeEntries.firstIndex(where: { $0.id == entryID }) {
                    self?.activeEntries[idx].stringValue = newVal
                }
            }
        )
    }

    func deleteEntry(entryID: UUID) {
        activeEntries.removeAll { $0.id == entryID }
    }

    func removeArrayItem(entryID: UUID, index: Int) {
        if let idx = activeEntries.firstIndex(where: { $0.id == entryID }),
           activeEntries[idx].arrayValue.indices.contains(index) {
            activeEntries[idx].arrayValue.remove(at: index)
        }
    }

    func addArrayItem(entryID: UUID) {
        let trimmed = newArrayItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = activeEntries.firstIndex(where: { $0.id == entryID }) {
            activeEntries[idx].arrayValue.append(trimmed)
            newArrayItemText = ""
        }
    }

    func addKnownEntitlement(_ entitlement: Entitlement) {
        let template = entitlement.defaultTemplate(bundleID: bundleID)
        let entry: EntitlementEntry
        switch entitlement.valueType {
        case .boolean:
            entry = EntitlementEntry(
                key: entitlement.rawValue,
                type: .boolean,
                boolValue: (template as? Bool) ?? true,
                isAppDefault: false
            )
        case .string:
            entry = EntitlementEntry(
                key: entitlement.rawValue,
                type: .string,
                stringValue: (template as? String) ?? "",
                isAppDefault: false
            )
        case .stringArray:
            entry = EntitlementEntry(
                key: entitlement.rawValue,
                type: .stringArray,
                arrayValue: (template as? [String]) ?? [],
                isAppDefault: false
            )
        case .number:
            entry = EntitlementEntry(
                key: entitlement.rawValue,
                type: .number,
                stringValue: "\(template)",
                isAppDefault: false
            )
        }
        activeEntries.append(entry)
    }

    func resetCustomKeyFields() {
        newCustomKey = ""
        newCustomString = ""
        newCustomBool = true
        newCustomArrayText = ""
        newCustomType = .boolean
        isShowingAddCustomSheet = true
    }

    func commitCustomKey() {
        let key = newCustomKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        let arrayVal: [String]
        if newCustomType == .stringArray {
            arrayVal = newCustomArrayText
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            arrayVal = []
        }

        let entry = EntitlementEntry(
            key: key,
            type: newCustomType,
            boolValue: newCustomBool,
            stringValue: newCustomString.trimmingCharacters(in: .whitespacesAndNewlines),
            arrayValue: arrayVal,
            isAppDefault: false
        )
        activeEntries.append(entry)
    }

    func handleProceed() {
        var result: [String: any Sendable] = [:]

        for entry in activeEntries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            guard isEntitlementAllowed(key) else {
                continue
            }

            switch entry.type {
            case .boolean:
                result[key] = entry.boolValue
            case .string:
                result[key] = entry.stringValue
            case .stringArray:
                result[key] = entry.arrayValue
            case .number:
                if let intVal = Int(entry.stringValue) {
                    result[key] = intVal
                } else if let doubleVal = Double(entry.stringValue) {
                    result[key] = doubleVal
                } else {
                    result[key] = entry.stringValue
                }
            }
        }

        onProceed(result)
    }
}
