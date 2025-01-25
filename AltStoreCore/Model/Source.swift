//
//  Source.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import UIKit

public extension Source
{
    static let altStoreIdentifier = try! Source.sourceID(from: Source.altStoreSourceURL)
    
    #if STAGING
    
    #if ALPHA
    static let altStoreSourceURL = URL(string: "https://apps.sidestore.io/")!
    #else
    static let altStoreSourceURL = URL(string: "https://apps.sidestore.io/")!
    #endif
    
    #else
    
    #if ALPHA
    static let altStoreSourceURL = URL(string: "https://apps.sidestore.io/")!
    #else
//    static let altStoreSourceURL = URL(string: "https://apps.sidestore.io/")!
    static let altStoreSourceURL = URL(string: "https://mahee96.github.io/apps-v2.json/")!       // using v2 for alpha releases
    #endif
    
    #endif
}




public struct AppPermissionFeed: Codable {
    let type: String // ALTAppPermissionType
    let usageDescription: String
       
    enum CodingKeys: String, CodingKey
    {
        case type
        case usageDescription
    }
}

// added in 0.6.0
public struct AppReleaseTrack: Codable {
    /* Properties */
    let alpha:  [AppVersionFeed]
    let beta:   [AppVersionFeed]
    let stable: [AppVersionFeed]
    
    enum CodingKeys: String, CodingKey
    {
        // added in 0.6.0
        case alpha
        case beta
        case stable
    }
}

public struct AppVersionFeed: Codable {
    /* Properties */
    let version: String
    let date: Date
    let localizedDescription: String?
    let downloadURL: URL
    let size: Int64
    // added in 0.6.0
    let sha256: String?     // sha 256 of the uploaded IPA
    let revision: String?   // commit ID for now
    
    enum CodingKeys: String, CodingKey
    {
        case version
        case date
        case localizedDescription
        case downloadURL
        case size
        // added in 0.6.0
        case sha256
        case revision = "commitID"
    }
}

public struct PlatformURLFeed: Codable {
    /* Properties */
    let platform: Platform
    let downloadURL: URL
    
    
    private enum CodingKeys: String, CodingKey
    {
        case platform
        case downloadURL
    }
}

public struct StoreAppFeed: Codable {

    let name: String
    let bundleIdentifier: String
    let developerName: String
    let version: String
    let versionDate: Date
    let versionDescription: String?
    let size: Int64
    let localizedDescription: String
    let iconURL: URL
    let tintColor: String? // UIColor?
    let downloadURL: URL
    let sha256: String?
    let screenshotURLs: [URL]
    let releaseTrack: AppReleaseTrack
    let appPermission: [AppPermissionFeed]

//    let source: Source?
    let subtitle: String?
    let platformURLs: [PlatformURLFeed]?
    
    enum CodingKeys: String, CodingKey
    {
        case name
        case bundleIdentifier
        case developerName
        case version
        case versionDate
        case versionDescription
        case size
        case localizedDescription
        case iconURL
        case tintColor
        case downloadURL
        case sha256
        case screenshotURLs
        case releaseTrack = "releaseChannels"
        case appPermission = "permissions"

        case subtitle
        case platformURLs
    }
}

public struct NewsItemFeed: Codable {
    
    let title: String
    let identifier: String
    let caption: String
    let tintColor: String //UIColor
    let externalURL: URL?
    let imageURL: URL?
    let date: Date
    let notify: Bool
    let appID: String?
    
    private enum CodingKeys: String, CodingKey
    {
        case title
        case identifier
        case caption
        case tintColor
        case imageURL
        case externalURL = "url"
        case date
        case notify
        case appID
    }
}

public struct SourceJSON: Codable {
    let version: Int?   // keep it optional(for coredata) until all users migrate to this version and remove it later
    let name: String
    let identifier: String
    let sourceURL: URL
    let userInfo: [String:String]? //[ALTSourceUserInfoKey:String]?
    let apps: [StoreAppFeed]
    let news: [NewsItemFeed]
    
    enum CodingKeys: String, CodingKey
    {
        case version
        case name
        case identifier
        case sourceURL
        case userInfo
        case apps
        case news
    }
    
}





public extension Source
{
    // Fallbacks for optional JSON values.
    
    var effectiveIconURL: URL? {
        return self.iconURL ?? self.apps.first?.iconURL
    }
    
    var effectiveHeaderImageURL: URL? {
        return self.headerImageURL ?? self.effectiveIconURL
    }
    
    var effectiveTintColor: UIColor? {
        return self.tintColor ?? self.apps.first?.tintColor
    }
    
    var effectiveFeaturedApps: [StoreApp] {
        return self.featuredApps ?? self.apps
    }
}





@objc(Source)
public class Source: NSManagedObject, Fetchable, Decodable
{
    /* Properties */
    @NSManaged public var version: Int
    @NSManaged public var name: String
    @NSManaged public private(set) var identifier: String
    @NSManaged public var sourceURL: URL
    
    /* Source Detail */
    @NSManaged public var subtitle: String?
    @NSManaged public var localizedDescription: String?
    @NSManaged public var websiteURL: URL?
    @NSManaged public var patreonURL: URL?
    
    // Optional properties with fallbacks.
    // `private` to prevent accidentally using instead of `effective[PropertyName]`
    @NSManaged private var iconURL: URL?
    @NSManaged private var headerImageURL: URL?
    @NSManaged private var tintColor: UIColor?
    
    @NSManaged public var error: NSError?
    
    @NSManaged public var featuredSortID: String?
    
    /* Non-Core Data Properties */
    public var userInfo: [ALTSourceUserInfoKey: String]?
    
    /* Relationships */
    @objc(apps) @NSManaged public private(set) var _apps: NSOrderedSet
    @objc(newsItems) @NSManaged public private(set) var _newsItems: NSOrderedSet
    
    @objc(featuredApps) @NSManaged public private(set) var _featuredApps: NSOrderedSet
    @objc(hasFeaturedApps) @NSManaged private var _hasFeaturedApps: Bool
    
    @nonobjc public var apps: [StoreApp] {
        get {
            return self._apps.array as! [StoreApp]
        }
        set {
            self._apps = NSOrderedSet(array: newValue)
        }
    }
    
    @nonobjc public var newsItems: [NewsItem] {
        get {
            return self._newsItems.array as! [NewsItem]
        }
        set {
            self._newsItems = NSOrderedSet(array: newValue)
        }
    }
    
    // `internal` to prevent accidentally using instead of `effectiveFeaturedApps`
    @nonobjc internal var featuredApps: [StoreApp]? {
        return self._hasFeaturedApps ? self._featuredApps.array as? [StoreApp] : nil
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case version
        case name
        case sourceURL
        case subtitle
        case localizedDescription = "description"
        case iconURL
        case headerImageURL = "headerURL"
        case websiteURL = "website"
        case tintColor
        case patreonURL
        
        case apps
        case news
        case featuredApps
        case userInfo
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        guard let sourceURL = decoder.sourceURL else { preconditionFailure("Decoder must have non-nil sourceURL.") }
        
        super.init(entity: Source.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            
            // Optional Values
            
            // use sourceversion = 1 by default if not specified in source json
            self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            
            self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            self.websiteURL = try container.decodeIfPresent(URL.self, forKey: .websiteURL)
            self.localizedDescription = try container.decodeIfPresent(String.self, forKey: .localizedDescription)
            self.iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)
            self.headerImageURL = try container.decodeIfPresent(URL.self, forKey: .headerImageURL)
            self.patreonURL = try container.decodeIfPresent(URL.self, forKey: .patreonURL)
            
            if let tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColor)
            {
                guard let tintColor = UIColor(hexString: tintColorHex) else {
                    throw DecodingError.dataCorruptedError(forKey: .tintColor, in: container, debugDescription: "Hex code is invalid.")
                }
                
                self.tintColor = tintColor
            }
            
            let userInfo = try container.decodeIfPresent([String: String].self, forKey: .userInfo)
            self.userInfo = userInfo?.reduce(into: [:]) { $0[ALTSourceUserInfoKey($1.key)] = $1.value }
            
            // get the "apps" object
            let isApiV3: Bool = version > 2
            let apps = isApiV3 ?
                (try container.decodeIfPresent([StoreAppV2].self, forKey: .apps) ?? []) :
                (try container.decodeIfPresent([StoreApp].self, forKey: .apps) ?? [])
            
            let appsByID = Dictionary(apps.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { (a, b) in return a })
            
            for (index, app) in apps.enumerated()
            {
                app.sortIndex = Int32(index)
            }
            self._apps = NSMutableOrderedSet(array: apps)
            
            let newsItems = try container.decodeIfPresent([NewsItem].self, forKey: .news) ?? []
            for (index, item) in newsItems.enumerated()
            {
                item.sortIndex = Int32(index)
            }
                                
            for newsItem in newsItems
            {
                guard let appID = newsItem.appID else { continue }
                
                if let storeApp = appsByID[appID]
                {
                    newsItem.storeApp = storeApp
                }
                else
                {
                    newsItem.storeApp = nil
                }
            }
            self._newsItems = NSMutableOrderedSet(array: newsItems)
            
            let featuredAppBundleIDs = try container.decodeIfPresent([String].self, forKey: .featuredApps)
            let featuredApps = featuredAppBundleIDs?.compactMap { appsByID[$0] }
            self.setFeaturedApps(featuredApps)
            
            // Updates identifier + apps & newsItems
            try self.setSourceURL(sourceURL)
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

public extension Source
{
    // Source is considered added IFF it has been saved to disk,
    // which we can check by fetching on a new managed object context.
    var isAdded: Bool {
        get async throws {
            let identifier = await AsyncManaged(wrappedValue: self).identifier
            let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            
            let isAdded = try await backgroundContext.performAsync {
                let fetchRequest = Source.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(Source.identifier), identifier)
                
                let count = try backgroundContext.count(for: fetchRequest)
                return (count > 0)
            }
            
            return isAdded
        }
    }
    
    var isRecommended: Bool {
        guard let recommendedSources = UserDefaults.shared.recommendedSources else { return false }
        
        // TODO: Support alternate URLs
        let isRecommended = recommendedSources.contains { source in
            return source.identifier == self.identifier || source.sourceURL?.absoluteString.lowercased() == self.sourceURL.absoluteString
        }
        return isRecommended
    }
    
    var lastUpdatedDate: Date? {
        let allDates = self.apps.compactMap { $0.latestAvailableVersion?.date } + self.newsItems.map { $0.date }
        
        let lastUpdatedDate = allDates.sorted().last
        return lastUpdatedDate
    }
}

internal extension Source
{
    class func sourceID(from sourceURL: URL) throws -> String
    {
        let sourceID = try sourceURL.normalized()
        return sourceID
    }
    
    func setFeaturedApps(_ featuredApps: [StoreApp]?)
    {
        // Explicitly update relationships for all apps to ensure featuredApps merges correctly.
        
        for case let storeApp as StoreApp in self._apps
        {
            if let featuredApps, featuredApps.contains(where: { $0.bundleIdentifier == storeApp.bundleIdentifier })
            {
                storeApp.featuringSource = self
            }
            else
            {
                storeApp.featuringSource = nil
            }
        }
        
        self._featuredApps = NSOrderedSet(array: featuredApps ?? [])
        self._hasFeaturedApps = (featuredApps != nil)
    }
}

public extension Source
{
    func setSourceURL(_ sourceURL: URL) throws
    {
        let identifier = try Source.sourceID(from: sourceURL)

        self.identifier = identifier
        self.sourceURL = sourceURL
        
        for app in self.apps
        {
            app.sourceIdentifier = identifier
        }
        
        for newsItem in self.newsItems 
        {
            newsItem.sourceIdentifier = identifier
        }
    }
}

public extension Source
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<Source>
    {
        return NSFetchRequest<Source>(entityName: "Source")
    }
    
    class func makeAltStoreSource(in context: NSManagedObjectContext) -> Source
    {
        let source = Source(context: context)
        source.name = "SideStore Offical"
        source.identifier = Source.altStoreIdentifier
        try! source.setSourceURL(Source.altStoreSourceURL)
        
        return source
    }
    
    class func fetchAltStoreSource(in context: NSManagedObjectContext) -> Source?
    {
        let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), Source.altStoreIdentifier), in: context)
        return source
    }
    
    class func make(name: String, identifier: String, sourceURL: URL, context: NSManagedObjectContext) -> Source
    {
        let source = Source(context: context)
        source.name = name
        source.identifier = identifier
        source.sourceURL = sourceURL
        
        return source
    }
}
