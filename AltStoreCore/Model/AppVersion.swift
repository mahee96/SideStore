//
//  AppVersion.swift
//  AltStoreCore
//
//  Created by Riley Testut on 8/18/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import CoreData

@objc(AppVersion)
public class AppVersion: NSManagedObject, Decodable, Fetchable
{
    /* Properties */
    @NSManaged public var version: String
    
    // NULL does not work as expected with SQL Unique Constraints (because NULL != NULL),
    // so we store non-optional value and provide public accessor with optional return type.
    @nonobjc public var buildVersion: String? {
        get { _buildVersion.isEmpty ? nil : _buildVersion }
        set { _buildVersion = newValue ?? "" }
    }
    @NSManaged @objc(buildVersion) public private(set) var _buildVersion: String
    
    @NSManaged public var date: Date
    @NSManaged public var localizedDescription: String?
    @NSManaged public var downloadURL: URL
    @NSManaged public var size: Int64
    @NSManaged public var sha256: String?
    
    @nonobjc public var minOSVersion: OperatingSystemVersion? {
        guard let osVersionString = self._minOSVersion else { return nil }
        
        let osVersion = OperatingSystemVersion(string: osVersionString)
        return osVersion
    }
    @NSManaged @objc(minOSVersion) private var _minOSVersion: String?
    
    @nonobjc public var maxOSVersion: OperatingSystemVersion? {
        guard let osVersionString = self._maxOSVersion else { return nil }
        
        let osVersion = OperatingSystemVersion(string: osVersionString)
        return osVersion
    }
    @NSManaged @objc(maxOSVersion) private var _maxOSVersion: String?
    
    @NSManaged public var appBundleID: String
    @NSManaged public var sourceID: String?
   
    @NSManaged public private(set) var revision: String?
    @NSManaged @objc(channel) private var _channel: String?
    @NSManaged public var releaseTrack: ReleaseTrack?

    /* Relationships */
    @NSManaged @objc(app) private var _app: StoreApp?
    @NSManaged @objc(latestVersionApp) public internal(set) var latestSupportedVersionApp: StoreApp?
    
    // public accessors
    public var app: StoreApp? {
        // try to get from v2 releaseTrack inverse relationship if present else fallback to direct inverse relationship
        // (assuming storeApp v1 is using us)
        return releaseTrack?.storeApp ?? _app
    }

    public var channel: ReleaseTrack.CodingKeys {
        get{
            ReleaseTrack.channel(for: self._channel)
        }
        set {
            self._channel = newValue.rawValue
        }
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    internal enum CodingKeys: String, CodingKey
    {
        case version
        case buildVersion
        case date
        case localizedDescription
        case downloadURL
        case size
        case sha256
        case minOSVersion
        case maxOSVersion
        case revision = "commitID"
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: AppVersion.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.version = try container.decode(String.self, forKey: .version)
            self.buildVersion = try container.decodeIfPresent(String.self, forKey: .buildVersion)
            
            self.date = try container.decode(Date.self, forKey: .date)
            self.localizedDescription = try container.decodeIfPresent(String.self, forKey: .localizedDescription)
            
            self.downloadURL = try container.decode(URL.self, forKey: .downloadURL)
            self.size = try container.decode(Int64.self, forKey: .size)
            
            self.sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)?.lowercased()
            self._minOSVersion = try container.decodeIfPresent(String.self, forKey: .minOSVersion)
            self._maxOSVersion = try container.decodeIfPresent(String.self, forKey: .maxOSVersion)

            self.revision = try container.decodeIfPresent(String.self, forKey: .revision)
        }
        catch
        {
            if let context = self.managedObjectContext
            {
                context.delete(self)
            }
            
            throw error
        }
    }
}

public extension AppVersion
{
    var localizedVersion: String {
        guard let buildVersion else { return self.version }
        
        let localizedVersion = "\(self.version) (\(buildVersion))"
        return localizedVersion
    }
    
    var versionID: String {
        // Use `nil` as fallback to prevent collisions between versions with builds and versions without.
        // 1.5 (4) -> "1.5|4"
        // 1.5.4 (no build) -> "1.5.4|nil"
        let buildVersion = self.buildVersion ?? "nil"
        
        let versionID = "\(self.version)|\(buildVersion)"
        return versionID
    }
}

public extension AppVersion
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppVersion>
    {
        return NSFetchRequest<AppVersion>(entityName: "AppVersion")
    }
    
    // this creates an entry into context(for each instantiation), so don't invoke unnessarily for temp things
    // create once and use mutateForData() to update it if required
    class func makeAppVersion(
        version: String,
        channel: ReleaseTrack.CodingKeys? = nil,
        buildVersion: String?,
        date: Date,
        localizedDescription: String? = nil,
        downloadURL: URL,
        size: Int64,
        revision: String? = nil,        // by default assume release is stable ie, no revision info
        sha256: String? = nil,
        appBundleID: String,
        sourceID: String? = nil,
        in context: NSManagedObjectContext) -> AppVersion
    {
        let appVersion = AppVersion(context: context)
        appVersion._channel = channel?.rawValue
        appVersion.version = version
        appVersion.buildVersion = buildVersion
        appVersion.date = date
        appVersion.localizedDescription = localizedDescription
        appVersion.downloadURL = downloadURL
        appVersion.size = size
        appVersion.sha256 = sha256
        appVersion.revision = revision
        appVersion.appBundleID = appBundleID
        appVersion.sourceID = sourceID

        return appVersion
    }
    
    // update with new values
    func mutateForData(
        version: String? = nil,
        channel: ReleaseTrack.CodingKeys? = nil,
        buildVersion: String? = nil,
        date: Date? = nil,
        localizedDescription: String? = nil,
        downloadURL: URL? = nil,
        size: Int64? = nil,
        revision: String? = nil,        // by default assume release is stable ie, no revision info
        sha256: String? = nil,
        appBundleID: String? = nil,
        sourceID: String? = nil) -> AppVersion
    {
        // use overrding incoming params if present else retain existing
        self.version = version ?? self.version
        self.channel = channel ?? self.channel
        self.buildVersion = buildVersion ?? self.buildVersion
        self.date = date ?? self.date
        self.localizedDescription = localizedDescription ?? self.localizedDescription
        self.downloadURL = downloadURL ?? self.downloadURL
        self.size = size ?? self.size
        self.sha256 = sha256 ?? self.sha256
        self.revision = revision ?? self.revision
        self.appBundleID = appBundleID ?? self.appBundleID
        self.sourceID = sourceID ?? self.sourceID

        return self
    }
    
    
    var isSupported: Bool {
        if let minOSVersion = self.minOSVersion, !ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion)
        {
            return false
        }
        else if let maxOSVersion = self.maxOSVersion, ProcessInfo.processInfo.operatingSystemVersion > maxOSVersion
        {
            return false
        }

        return true
    }
}
