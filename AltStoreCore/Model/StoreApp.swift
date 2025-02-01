//
//  StoreApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import Roxas
import AltSign

public extension StoreApp
{
    #if ALPHA
    static let altstoreAppID = Bundle.Info.appbundleIdentifier
    #elseif BETA
    static let altstoreAppID = Bundle.Info.appbundleIdentifier
    #else
    static let altstoreAppID = Bundle.Info.appbundleIdentifier
    #endif
    
    static let dolphinAppID = "me.oatmealdome.dolphinios-njb"
}

@objc
public enum Platform: UInt, Codable {
    case ios
    case tvos
    case macos
}

@objc
public final class PlatformURL: NSManagedObject, Decodable {
    /* Properties */
    @NSManaged public private(set) var platform: Platform
    @NSManaged public private(set) var downloadURL: URL
    
    
    private enum CodingKeys: String, CodingKey
    {
        case platform
        case downloadURL
    }
    
    
    public init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        // Must initialize with context in order for child context saves to work correctly.
        super.init(entity: PlatformURL.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.platform = try container.decode(Platform.self, forKey: .platform)
            self.downloadURL = try container.decode(URL.self, forKey: .downloadURL)
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

extension PlatformURL: Comparable {
    public static func < (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue < rhs.platform.rawValue
    }
    
    public static func > (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue > rhs.platform.rawValue
    }
    
    public static func <= (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue <= rhs.platform.rawValue
    }
    
    public static func >= (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue >= rhs.platform.rawValue
    }
}

public typealias PlatformURLs = [PlatformURL]

private struct PatreonParameters: Decodable
{
    struct Pledge: Decodable
    {
        var amount: Decimal
        var isCustom: Bool
        
        init(from decoder: Decoder) throws
        {
            let container = try decoder.singleValueContainer()
            
            if let stringValue = try? container.decode(String.self), stringValue == "custom"
            {
                self.amount = 0 // Use 0 as amount internally to simplify logic.
                self.isCustom = true
            }
            else
            {
                // Unless the value is "custom", throw error if value is not Decimal.
                self.amount = try container.decode(Decimal.self)
                self.isCustom = false
            }
        }
    }
    
    var pledge: Pledge?
    var currency: String?
    var tiers: Set<String>?
    var benefit: String?
    var hidden: Bool?
}

@objc(StoreApp)
public class StoreApp: BaseEntity, Decodable
{
    /* Properties */
    @NSManaged public private(set) var name: String
    @NSManaged public private(set) var bundleIdentifier: String
    @NSManaged public private(set) var subtitle: String?
    
    @NSManaged public private(set) var developerName: String
    @NSManaged public private(set) var localizedDescription: String
    @NSManaged @objc(size) internal var _size: Int32
    
    @nonobjc public var category: StoreCategory? {
        guard let _category else { return nil }
        
        let category = StoreCategory(rawValue: _category)
        return category
    }
    @NSManaged @objc(category) public private(set) var _category: String?
    
    @NSManaged public private(set) var iconURL: URL
    @NSManaged public private(set) var screenshotURLs: [URL]
    
    @NSManaged @objc(downloadURL) internal var _downloadURL: URL
    @NSManaged public private(set) var platformURLs: PlatformURLs?

    @NSManaged public private(set) var tintColor: UIColor?

    @NSManaged @objc(channel) var _channel: String?
    
    // Required for Marketplace apps.
    @NSManaged public private(set) var marketplaceID: String?

    @NSManaged public var isPledged: Bool
    @NSManaged public private(set) var isPledgeRequired: Bool
    @NSManaged public private(set) var isHiddenWithoutPledge: Bool
    @NSManaged public private(set) var pledgeCurrency: String?
    @NSManaged public private(set) var prefersCustomPledge: Bool
    
    @nonobjc public var pledgeAmount: Decimal? { _pledgeAmount as? Decimal }
    @NSManaged @objc(pledgeAmount) private var _pledgeAmount: NSDecimalNumber?
    
    @NSManaged public var sortIndex: Int32
    @NSManaged public var featuredSortID: String?
    
    @objc public internal(set) var sourceIdentifier: String? {
        get {
            self.willAccessValue(forKey: #keyPath(sourceIdentifier))
            defer { self.didAccessValue(forKey: #keyPath(sourceIdentifier)) }
            
            let sourceIdentifier = self.primitiveSourceIdentifier
            return sourceIdentifier
        }
        set {
            self.willChangeValue(forKey: #keyPath(sourceIdentifier))
            self.primitiveSourceIdentifier = newValue
            self.didChangeValue(forKey: #keyPath(sourceIdentifier))
            
            for version in self.versions
            {
                version.sourceID = newValue
            }
            
            for permission in self.permissions
            {
                permission.sourceID = self.sourceIdentifier ?? ""
            }
            
            for screenshot in self.screenshots
            {
                screenshot.sourceID = self.sourceIdentifier ?? ""
            }
        }
    }
    @NSManaged private var primitiveSourceIdentifier: String?
    
    // Legacy (kept for backwards compatibility)
    @NSManaged @objc(version) internal private(set) var _version: String
    @NSManaged @objc(versionDate) internal private(set) var _versionDate: Date
    @NSManaged @objc(versionDescription) internal private(set) var _versionDescription: String?
    
    /* Relationships */
    @NSManaged public var installedApp: InstalledApp?
    @NSManaged public var newsItems: Set<NewsItem>
    
    @NSManaged @objc(source) public var _source: Source?
    @NSManaged public internal(set) var featuringSource: Source?
    
    @NSManaged @objc(latestVersion) public private(set) var latestSupportedVersion: AppVersion?
    @NSManaged @objc(versions) public private(set) var _versions: NSOrderedSet
    
    @NSManaged public private(set) var loggedErrors: NSSet /* Set<LoggedError> */ // Use NSSet to avoid eagerly fetching values.
    
    /* Non-Core Data Properties */
    
    // Used to set isPledged after fetching source.
    public var _tierIDs: Set<String>?
    public var _rewardID: String?

    @nonobjc public var source: Source? {
        set {
            self._source = newValue
            self.sourceIdentifier = newValue?.identifier
        }
        get {
            return self._source
        }
    }

//    public var channel: ReleaseTracks {
//        get{
//            ReleaseTracks.channel(for: self._channel)
//        }
//        set {
//            self._channel = newValue.rawValue
//        }
//    }

    
    @nonobjc public var permissions: Set<AppPermission> {
        return self._permissions as! Set<AppPermission>
    }
    @NSManaged @objc(permissions) internal private(set) var _permissions: NSSet // Use NSSet to avoid eagerly fetching values.
    
    @nonobjc public var versions: [AppVersion] {
        return self._versions.array as? [AppVersion] ?? []
    }
    
    @nonobjc public var size: Int64? {
        guard let version = self.latestSupportedVersion else { return nil }
        return version.size
    }
    
    @nonobjc public var version: String? {
        guard let version = self.latestSupportedVersion else { return nil }
        return version.version
    }
    
    @nonobjc public var versionDescription: String? {
        guard let version = self.latestSupportedVersion else { return nil }
        return version.localizedDescription
    }
    
    @nonobjc public var versionDate: Date? {
        guard let version = self.latestSupportedVersion else { return nil }
        return version.date
    }
    
    @nonobjc public var downloadURL: URL? {
        guard let version = self.latestSupportedVersion else { return nil }
        return version.downloadURL
    }
    @nonobjc public var screenshots: [AppScreenshot] {
        return self._screenshots.array as! [AppScreenshot]
    }
    @NSManaged @objc(screenshots) private(set) var _screenshots: NSOrderedSet
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case bundleIdentifier
        case marketplaceID
        case developerName
        case localizedDescription
        case iconURL
        case platformURLs
        case screenshots
        case tintColor
        case subtitle
        case permissions = "appPermissions"
        case size
        case versions
        case patreon
        case category
        
        case channel
        
        // Legacy
        case version
        case versionDescription
        case versionDate
        case downloadURL
        case screenshotURLs
        case isBeta = "beta"
    }
    
    
    internal override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        // Must initialize with context in order for child context saves to work correctly.
        super.init(entity: Self.entity(), insertInto: context)
        try self.decode(from: decoder)
    }
    
    internal func decode(from decoder: Decoder) throws {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }

        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.name = try container.decode(String.self, forKey: .name)
            self.bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
            self.developerName = try container.decode(String.self, forKey: .developerName)
            self.localizedDescription = try container.decode(String.self, forKey: .localizedDescription)
            self.iconURL = try container.decode(URL.self, forKey: .iconURL)
            
            self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            
            // since decode essentially inserts an entry into insertedObjects of context and scheduling them for persistence,
            // we will decode only once
            let appVersions = try container.decodeIfPresent([AppVersion].self, forKey: .versions)
            if versions.isEmpty, let appVersions
            {
                self._versions = NSOrderedSet(array: appVersions)
            }
           
            let platformURLs = try container.decodeIfPresent(PlatformURLs.self.self, forKey: .platformURLs)
            if let platformURLs = platformURLs {
                self.platformURLs = platformURLs
                // Backwards compatibility, use the fiirst (iOS will be first since sorted that way)
                if let first = platformURLs.sorted().first {
                    self._downloadURL = first.downloadURL
                } else {
                    throw DecodingError.dataCorruptedError(forKey: .platformURLs, in: container, debugDescription: "platformURLs has no entries")

                }
            } else if let downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL) {
                self._downloadURL = downloadURL
            } else {
                // for backward compatibility until sources like https://altstore.ignitedemulator.com get updated to v2
                let error = DecodingError.dataCorruptedError(forKey: .downloadURL, in: container, debugDescription: "E downloadURL:String or downloadURLs:[[Platform:URL]] key required.")
                let version = try container.decodeIfPresent(String.self, forKey: .version)  // actual storeApp version is deduced later in setVersions() so this is just temp field

                guard let downloadURL = versions.first(where: { $0.version == version })?.downloadURL ?? versions.first?.downloadURL else
                {
                        throw error 
                }


                self._downloadURL = downloadURL
            }

            if let tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColor)
            {
                guard let tintColor = UIColor(hexString: tintColorHex) else {
                    throw DecodingError.dataCorruptedError(forKey: .tintColor, in: container, debugDescription: "Hex code is invalid.")
                }
                
                self.tintColor = tintColor
            }
            
            if let rawCategory = try container.decodeIfPresent(String.self, forKey: .category)
            {
                self._category = rawCategory.lowercased() // Store raw (lowercased) category value.
            }
            
            let appScreenshots: [AppScreenshot]
            
            if let screenshots = try container.decodeIfPresent(AppScreenshots.self, forKey: .screenshots)
            {
                appScreenshots = screenshots.screenshots
            }
            else if let screenshotURLs = try container.decodeIfPresent([URL].self, forKey: .screenshotURLs)
            {
                // Assume 9:16 iPhone 8 screen dimensions for legacy screenshotURLs.
                let legacyAspectRatio = CGSize(width: 750, height: 1334)
                
                appScreenshots = screenshotURLs.map { imageURL in
                    let screenshot = AppScreenshot(imageURL: imageURL, size: legacyAspectRatio, deviceType: .iphone, context: context)
                    return screenshot
                }
            }
            else
            {
                appScreenshots = []
            }
   
            for screenshot in appScreenshots
            {
                screenshot.appBundleID = self.bundleIdentifier
            }
            
            self.setScreenshots(appScreenshots)
            
            if let appPermissions = try container.decodeIfPresent(AppPermissions.self, forKey: .permissions)
            {
                let allPermissions = appPermissions.entitlements + appPermissions.privacy
                for permission in allPermissions
                {
                    permission.appBundleID = self.bundleIdentifier
                }
                
                self._permissions = NSSet(array: allPermissions)
            }
            else
            {
                self._permissions = NSSet()
            }
            
            if !versions.isEmpty
            {
                //TODO: Throw error if there isn't at least one version.
                if (versions.count == 0){
                    throw DecodingError.dataCorruptedError(forKey: .versions, in: container, debugDescription: "At least one version is required in key: versions")
                }

                for (index, version) in zip(0..., versions)
                {
                    version.appBundleID = self.bundleIdentifier

                    if self.marketplaceID != nil
                    {
                        struct IndexCodingKey: CodingKey
                        {
                            var stringValue: String { self.intValue?.description ?? "" }
                            var intValue: Int?

                            init?(stringValue: String)
                            {
                                fatalError()
                            }

                            init(intValue: Int)
                            {
                                self.intValue = intValue
                            }
                        }

                        // Marketplace apps must provide build version.
                        guard version.buildVersion != nil else {
                            let codingPath = container.codingPath + [CodingKeys.versions as CodingKey] + [IndexCodingKey(intValue: index) as CodingKey]
                            let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Notarized apps must provide a build version.")
                            throw DecodingError.keyNotFound(AppVersion.CodingKeys.buildVersion, context)
                        }
                    }

                }
                
                try self.setVersions(versions)
            }
            else
            {
                // TODO: Think of a way to deal propagate this isBeta as a track/channelName into the created AppVersion
//                // special case: AltStore sources supports 'isBeta' in the StoreApp so we have it for backward compatibility
//                let isBeta = try container.decodeIfPresent(Bool.self, forKey: .isBeta) ?? false
//                if isBeta{
//                    self.channel = .beta
//                }
                
                let appVersion = try createNewAppVersion(decoder: decoder)
                try self.setVersions([appVersion])
            }
            // Required for Marketplace apps, but we'll verify later.
            self.marketplaceID = try container.decodeIfPresent(String.self, forKey: .marketplaceID)

            // Must _explicitly_ set to false to ensure it updates cached database value.
            self.isPledged = false
            self.prefersCustomPledge = false
            
            if let patreon = try container.decodeIfPresent(PatreonParameters.self, forKey: .patreon)
            {
                self.isPledgeRequired = true
                self.isHiddenWithoutPledge = patreon.hidden ?? false // Default to showing Patreon apps
                                
                if let pledge = patreon.pledge
                {
                    self._pledgeAmount = pledge.amount as NSDecimalNumber
                    self.pledgeCurrency = patreon.currency ?? "USD" // Only set pledge currency if explicitly given pledge.
                    self.prefersCustomPledge = pledge.isCustom
                }
                else if patreon.pledge == nil && patreon.tiers == nil && patreon.benefit == nil
                {
                    // No conditions, so default to pledgeAmount of 0 to simplify logic.
                    self._pledgeAmount = 0 as NSDecimalNumber
                }
                
                self._tierIDs = patreon.tiers
                self._rewardID = patreon.benefit
            }
            else
            {
                self.isPledgeRequired = false
                self.isHiddenWithoutPledge = false
                self._pledgeAmount = nil
                self.pledgeCurrency = nil
                
                self._tierIDs = nil
                self._rewardID = nil
            }
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
    
    
    public override func awakeFromInsert()
    {
        super.awakeFromInsert()
        
        self.featuredSortID = UUID().uuidString
    }
}

internal extension StoreApp
{
    @objc func getLatestSupportedVersion(_ versions: [AppVersion]) -> AppVersion? {
        let latestSupportedVersion = versions.first(where: { $0.isSupported })
        
        for case let version in versions
        {
            if version == latestSupportedVersion
            {
                version.latestSupportedVersionApp = self
            }
            else
            {
                // Ensure we replace any previous relationship when merging.
                version.latestSupportedVersionApp = self
            }
        }
        
        return latestSupportedVersion
    }
    
    func createNewAppVersion(decoder: Decoder) throws -> AppVersion {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        //
        let version = try container.decode(String.self, forKey: .version)
        let versionDate = try container.decode(Date.self, forKey: .versionDate)
        let versionDescription = try container.decodeIfPresent(String.self, forKey: .versionDescription)
        
        let downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        let size = try container.decode(Int32.self, forKey: .size)
        
        return AppVersion.makeAppVersion(version: version,
                                           buildVersion: nil,
                                           date: versionDate,
                                           localizedDescription: versionDescription,
                                           downloadURL: downloadURL,
                                           size: Int64(size),
                                           appBundleID: self.bundleIdentifier,
                                           in: context)
    }

    @objc func setVersions(_ versions: [AppVersion]) throws {
        
        guard let latestVersion = versions.first else {
            throw MergeError.noVersions(for: self)
        }

        self.latestSupportedVersion = getLatestSupportedVersion(versions)
        // Preserve backwards compatibility by assigning legacy property values.
        self._version = latestVersion.version
        self._versionDate = latestVersion.date
        self._versionDescription = latestVersion.localizedDescription
        self._downloadURL = latestVersion.downloadURL
        self._size = Int32(latestVersion.size)

        self._versions = NSOrderedSet(array: versions)
    }
    
    func setPermissions(_ permissions: Set<AppPermission>)
    {
        for case let permission as AppPermission in self._permissions
        {
            if permissions.contains(permission)
            {
                permission.app = self
            }
            else
            {
                permission.app = nil
            }
        }
        
        self._permissions = permissions as NSSet
    }
    
    func setScreenshots(_ screenshots: [AppScreenshot])
    {
        for case let screenshot as AppScreenshot in self._screenshots
        {
            if screenshots.contains(screenshot)
            {
                screenshot.app = self
            }
            else
            {
                screenshot.app = nil
            }
        }
        
        self._screenshots = NSOrderedSet(array: screenshots)
        
        // Backwards compatibility
        self.screenshotURLs = screenshots.map { $0.imageURL }
    }
}

public extension StoreApp
{
    func screenshots(for deviceType: ALTDeviceType) -> [AppScreenshot]
    {
        //TODO: Support multiple device types
        let filteredScreenshots = self.screenshots.filter { $0.deviceType == deviceType }
        return filteredScreenshots
    }
    
    func preferredScreenshots() -> [AppScreenshot]
    {
        let deviceType: ALTDeviceType
        
        if UIDevice.current.model.contains("iPad")
        {
            deviceType = .ipad
        }
        else
        {
            deviceType = .iphone
        }
        
        let preferredScreenshots = self.screenshots(for: deviceType)
        guard !preferredScreenshots.isEmpty else {
            // There are no screenshots for deviceType, so return _all_ screenshots instead.
            return self.screenshots
        }
        
        return preferredScreenshots
    }
}

public extension StoreApp
{
    @objc var latestAvailableVersion: AppVersion? {
        return self.versions.first
    }
    
    var globallyUniqueID: String? {
        guard let sourceIdentifier = self.sourceIdentifier else { return nil }
        
        let globallyUniqueID = self.bundleIdentifier + "|" + sourceIdentifier
        return globallyUniqueID
    }
}

public extension StoreApp
{
    class var visibleAppsPredicate: NSPredicate {
        let predicate = NSPredicate(format: "(%K != %@) AND ((%K == NO) OR (%K == NO) OR (%K == YES))",
                                    #keyPath(StoreApp.bundleIdentifier), StoreApp.altstoreAppID,
                                    #keyPath(StoreApp.isPledgeRequired),
                                    #keyPath(StoreApp.isHiddenWithoutPledge),
                                    #keyPath(StoreApp.isPledged))
        return predicate
    }
    
    class var otherCategoryPredicate: NSPredicate {
        let knownCategories = StoreCategory.allCases.lazy.filter { $0 != .other }.map { $0.rawValue }
        
        let predicate = NSPredicate(format: "%K == nil OR NOT (%K IN %@)", #keyPath(StoreApp._category), #keyPath(StoreApp._category), Array(knownCategories))
        return predicate
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<StoreApp>
    {
        return NSFetchRequest<StoreApp>(entityName: "StoreApp")
    }
    
    //MARK: - override in subclasses if required
    @objc func placeholderAppVersion(appVersion: AppVersion, in context: NSManagedObjectContext) -> AppVersion{
        return appVersion
    }
    //MARK: - override in subclasses if required
    @objc class func createStoreApp(in context: NSManagedObjectContext) -> StoreApp{
        return StoreApp(context: context)
    }
    
    
    class func isPlaceHolderVersion(_ version: AppVersion) -> Bool{
        return version.version == "0.0.0" && version.date == Date.distantPast && version.appBundleID == StoreApp.altstoreAppID
    }
    
    
    
    class func makeAltStoreApp(version: String, buildVersion: String?, in context: NSManagedObjectContext) -> StoreApp
    {
        let app = Self.createStoreApp(in: context)
        app.name = "SideStore"
        app.bundleIdentifier = StoreApp.altstoreAppID
        app.developerName = "Side Team"
        app.localizedDescription = "SideStore is an alternative App Store."
        app.iconURL = URL(string: "https://user-images.githubusercontent.com/705880/63392210-540c5980-c37b-11e9-968c-8742fc68ab2e.png")!
        app.screenshotURLs = []
        app._channel = ReleaseTracks.stable.rawValue
        
        var appVersion = AppVersion.makeAppVersion(version: "0.0.0",
                                                   buildVersion: nil,
                                                   date: Date.distantPast,
//                                                   date: Date(timeIntervalSinceReferenceDate: 0),
//                                                   date: Date(timeIntervalSince1970: 0),
                                                   downloadURL: URL(string: "https://sidestore.io")!,
                                                   size: 0,
                                                   appBundleID: StoreApp.altstoreAppID,
                                                   in: context)
        // update in sublasses if required
        appVersion = app.placeholderAppVersion(appVersion: appVersion, in: context)
        
        try? app.setVersions([appVersion])
        
        print("Creating a new Placeholder StoreApp: \n\(String(describing: app))")
        
        return app
    }
}
