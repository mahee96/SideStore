//
//  InfoPlistParser.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public struct InfoPlistParser: Sendable {
    public private(set) var rawDictionary: [String: Any]

    public init(dictionary: [String: Any]) {
        self.rawDictionary = dictionary
    }

    public init(data: Data) throws {
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw OperationError.invalidApp(reason: "Invalid PropertyList data format.")
        }
        self.rawDictionary = dict
    }

    public init(plistURL: URL) throws {
        let data = try Data(contentsOf: plistURL)
        try self.init(data: data)
    }

    public init(bundleURL: URL) throws {
        let plistURL = bundleURL.appendingPathComponent("Info.plist")
        try self.init(plistURL: plistURL)
    }

    public var bundleIdentifier: String? {
        (rawDictionary["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var appName: String {
        displayName ?? bundleName ?? "Unknown"
    }

    public var displayName: String? {
        rawDictionary["CFBundleDisplayName"] as? String
    }

    public var bundleName: String? {
        rawDictionary["CFBundleName"] as? String
    }

    public var executableName: String? {
        rawDictionary["CFBundleExecutable"] as? String
    }

    public var shortVersionString: String? {
        rawDictionary["CFBundleShortVersionString"] as? String
    }

    public var buildVersion: String? {
        rawDictionary["CFBundleVersion"] as? String
    }

    public var displayVersion: String {
        let short = shortVersionString
        let build = buildVersion
        if let short = short, let build = build {
            return "\(short) (\(build))"
        }
        return short ?? build ?? "N/A"
    }

    public var minimumOSVersion: String? {
        rawDictionary["MinimumOSVersion"] as? String
    }

    public var isFileSharingEnabled: Bool {
        rawDictionary["UIFileSharingEnabled"] as? Bool ?? false
    }

    public var supportsOpeningDocumentsInPlace: Bool {
        rawDictionary["LSSupportsOpeningDocumentsInPlace"] as? Bool ?? false
    }

    public var backgroundModes: [String] {
        rawDictionary["UIBackgroundModes"] as? [String] ?? []
    }

    public var customURLSchemes: [String] {
        guard let urlTypes = rawDictionary["CFBundleURLTypes"] as? [[String: Any]] else { return [] }
        return urlTypes.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
    }

    public var queriedURLSchemes: [String] {
        rawDictionary["LSApplicationQueriesSchemes"] as? [String] ?? []
    }

    public var privacyPermissions: [String: String] {
        var dict = [String: String]()
        for (key, val) in rawDictionary where key.hasPrefix("NS") && key.hasSuffix("UsageDescription") {
            if let str = val as? String { dict[key] = str }
        }
        return dict
    }

    public mutating func set(value: Any?, for key: String) {
        rawDictionary[key] = value
    }

    public mutating func merge(_ dictionary: [String: Any]) {
        for (key, value) in dictionary {
            rawDictionary[key] = value
        }
    }

    public func toXMLData() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: rawDictionary, format: .xml, options: 0)
    }

    public func toJSONData() throws -> Data {
        try JSONSerialization.data(withJSONObject: rawDictionary, options: [.prettyPrinted, .sortedKeys])
    }

    public func write(to url: URL) throws {
        let data = try toXMLData()
        try data.write(to: url, options: .atomic)
    }
}
