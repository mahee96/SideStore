//
//  AppreleaseTrack.swift
//  AltStore
//
//  Created by Magesh K on 19/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData

/// ReleaseTrack manages the categorization of AppVersions into different release channels (alpha/beta/stable).
///
/// Design Notes:
/// - ReleaseTrack is owned by StoreAppV2 with cascade deletion
/// - AppVersion can belong to only one ReleaseTrack at a time
/// - AppVersion is categorized into one of three channels (alpha/beta/stable)
/// - This is a "categorized one-to-many" relationship, not a true many-to-many
///   as AppVersions are dependent entities owned by their StoreApp/ReleaseTrack
///
/// Relationship Maintenance:
/// - Due to the categorized nature of relationships (alpha/beta/stable),
///   CoreData cannot automatically maintain inverse relationships
/// - Manual relationship maintenance is required during merges (see MergePolicy)
/// - When moving versions between channels, ensure both sides of relationship are updated
///

// created for 0.6.0
@objc(ReleaseTrack)
public class ReleaseTrack: NSManagedObject, Decodable, Fetchable
{
    // RelationShips
    @NSManaged @objc(alpha)  private var _alpha:   NSOrderedSet?
    @NSManaged @objc(beta)   private var _beta:    NSOrderedSet?
    @NSManaged @objc(stable) private var _stable:  NSOrderedSet?
    @NSManaged public private(set)    var storeApp: StoreAppV2?
    
    public enum CodingKeys: String, CodingKey, CaseIterable
    {
        case alpha
        case beta
        case stable
        case unknown
    }
    
    public static var betaTracks: [CodingKeys] {
        CodingKeys.allCases.filter(isBetaTrack)
    }

    public static var nonBetaTracks: [CodingKeys] {
        CodingKeys.allCases.filter { !isBetaTrack($0) }
    }

    private static func isBetaTrack(_ key: CodingKeys) -> Bool {
        key == .alpha || key == .beta
    }
    
    
    public func releasesFor(channel: CodingKeys) -> [AppVersion]? {
        switch channel{
        case .alpha:
            return self._alpha?.array as? [AppVersion]
        case .beta:
            return self._beta?.array as? [AppVersion]
        case .stable:
            return self._stable?.array as? [AppVersion]
        case .unknown:
            return nil
        }
    }
    
    public func latestRelease(for channel: CodingKeys) -> AppVersion? {
        let releases = releasesFor(channel: channel)
        return releases?.first
    }
    
    public func latestRelease(for channelName: String?) -> AppVersion? {
        let channel = Self.channel(for: channelName)
        return latestRelease(for: channel)
    }

    public class func channel(for channelName: String?) -> CodingKeys {
        let channelName = channelName ?? ""
        return CodingKeys(rawValue: channelName) ?? .unknown
    }
    
    
    // Required initializer for Core Data (context saves)
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public required init(from decoder: Decoder) throws{
        guard let context = decoder.managedObjectContext else {
            preconditionFailure("Decoder must have non-nil NSManagedObjectContext.")
        }
        
        // Must initialize with context in order for child context saves to work correctly.
        super.init(entity: ReleaseTrack.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self._alpha = try decodeTracks(forKey: .alpha, decoder: decoder)
            self._beta = try decodeTracks(forKey: .beta,  decoder: decoder)
            let stable = try decodeTracks(forKey: .stable, decoder: decoder)
            guard let stable = stable, stable.count > 0
            else {
                throw DecodingError.dataCorruptedError(forKey: .stable, in: container, debugDescription: "At least one version is required in key: stable")
            }
            self._stable = stable
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

public extension ReleaseTrack{
    /// Handles updating AppVersion fields that depend on StoreApp relationship
    ///
    /// Design Notes:
    /// - Uses KVO to observe storeApp relationship changes because:
    ///   1. ReleaseTrack has an inverse relationship to StoreAppV2
    ///   2. CoreData automatically sets storeApp after init() completes
    ///   3. Avoids manual setter methods for relationship management
    ///
    /// Warning:
    /// - Special handling required for deleted objects:
    ///   - CoreData sets all properties to nil during deletion
    ///   - This triggers KVO and could cause "mutating removed object" errors
    ///   - We guard against this by checking deletion state before updates
    ///
    internal func updateVersions(for storeApp: StoreApp?) {
        guard let storeApp = storeApp else { return }  // Just null check
        
        [_alpha, _beta, _stable].compactMap { $0 }.forEach { orderedSet in
            (orderedSet.array as? [AppVersion])?.forEach { version in
                // Only check deletion state for the object we're about to modify
                guard let context = version.managedObjectContext, !version.isDeleted,
                      !context.deletedObjects.contains(version) else { return }
                
                // never mutate objects that are being deleted or is already deleted
                version.appBundleID = storeApp.bundleIdentifier
            }
        }
    }
    
    /// Defer updates to fields that require storeApp inverse relationship to be set, which is not available in init(),
    /// by observing changes to the prop and update the data later
    ///
    /// NOTE: We use KVO here only coz, ReleaseTrack already has an inverse relationship to StoreAppV2
    ///       So coredata will actually set the storeApp but only issue is that it happens after init() is complete
    ///       hence we are using KVO so that one doesn't need to manually set the value via a setter method
    ///
    /// However this caused an issue when an object is marked deleted during merge policy conflict resolution, all its props are set to nil by coredata.
    /// this causes this KVO observer to be triggered and mutating the deleted entity causing a "coredata error: Mutating removed object"
    /// which is now handled by checking if context.deletedObjects doesn't contain it and version.isDeleted is not true yet
    /// 
    override func didChangeValue(forKey key: String) {
        super.didChangeValue(forKey: key)
        if key == NSExpression(forKeyPath: #keyPath(ReleaseTrack.storeApp)).keyPath
        {
            updateVersions(for: storeApp)
        }
    }
        
    private func decodeTracks(forKey channel: CodingKeys, decoder: Decoder) throws -> NSOrderedSet? {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let versions = try container.decodeIfPresent([AppVersion].self, forKey: channel) {
            for version in versions {
                version.channel = channel       // Set the channel
                version.releaseTrack = self     // Set the inverse relationship
            }
            return NSOrderedSet(array: versions)
        }
        return nil
    }
    
    
    // this creates an entry into context(for each instantiation), so don't invoke unnessarily for temp things
    // create once and use mutateForData() to update it if required
    class func makeReleaseTrack(
        alpha: [AppVersion]? = nil,
        beta: [AppVersion]? = nil,
        stable: [AppVersion]? = nil,
        in context: NSManagedObjectContext) -> ReleaseTrack
    {
        let releaseTrack = ReleaseTrack(context: context)
        releaseTrack._alpha = alpha.map{ NSOrderedSet(array: $0) }
        releaseTrack._beta = beta.map{ NSOrderedSet(array: $0) }
        releaseTrack._stable = stable.map{ NSOrderedSet(array: $0) }

        return releaseTrack
    }
    
    func mutateDataFor(
        alpha: [AppVersion]? = nil,
        beta: [AppVersion]? = nil,
        stable: [AppVersion]? = nil) -> ReleaseTrack
    {
        self._alpha = alpha.map{ NSOrderedSet(array: $0) } ?? self._alpha
        self._beta = beta.map{ NSOrderedSet(array: $0) } ?? self._beta
        self._stable = stable.map{ NSOrderedSet(array: $0) } ?? self._stable

        return self
    }
}
