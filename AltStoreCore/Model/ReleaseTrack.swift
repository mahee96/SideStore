//
//  AppreleaseTrack.swift
//  AltStore
//
//  Created by Magesh K on 19/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData

// created for 0.6.0
@objc(ReleaseTrack)
public class ReleaseTrack: NSManagedObject, Decodable, Fetchable
{
    // RelationShips
    @NSManaged @objc(alpha)  internal var _alpha:   NSOrderedSet?
    @NSManaged @objc(beta)   internal var _beta:    NSOrderedSet?
    @NSManaged @objc(stable) internal var _stable:  NSOrderedSet?
    @NSManaged public private(set)    var storeApp: StoreApp
    
    public enum CodingKeys: String, CodingKey
    {
        case alpha
        case beta
        case stable
        case unknown
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
            
//            self._alpha = try decodeChannel(forKey: .alpha, decoder: decoder)
//            self._beta = try decodeChannel(forKey: .beta,  decoder: decoder)
            let stable = try decodeChannel(forKey: .stable, decoder: decoder)
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
    
    func setStableReleases(_ versions: [AppVersion]) {
        self._stable = NSOrderedSet(array: versions)
    }
    
    private func decodeChannel(forKey channel: CodingKeys, decoder: Decoder) throws -> NSOrderedSet? {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let versions = try container.decodeIfPresent([AppVersion].self, forKey: channel) {
            for version in versions {
                version.channel = channel                       // Set the channel
                version.appBundleID = storeApp.bundleIdentifier      // Set the bundleID
                version.releaseTrack = self   // Set the inverse relationship
            }
            return NSOrderedSet(array: versions)
        }
        return nil
    }

    
//    private func decodeReleasesForChannel(_ channel: CodingKeys, In versions: [AppVersion]) -> [AppVersion]{
//        for (index, version) in zip(0..., versions)
////            {
////                if self.marketplaceID != nil
////                {
////                    struct IndexCodingKey: CodingKey
////                    {
////                        var stringValue: String { self.intValue?.description ?? "" }
////                        var intValue: Int?
////
////                        init?(stringValue: String)
////                        {
////                            fatalError()
////                        }
////
////                        init(intValue: Int)
////                        {
////                            self.intValue = intValue
////                        }
////                    }
////
////                    // Marketplace apps must provide build version.
////                    guard version.buildVersion != nil else {
////                        
////                        let codingPath = container.codingPath + [CodingKeys.versions as CodingKey] + [IndexCodingKey(intValue: index) as CodingKey]
////                        
////                        let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Notarized apps must provide a build version.")
////                        throw DecodingError.keyNotFound(AppVersion.CodingKeys.buildVersion, context)
////                    }
////                }
////
////            }
//        return versions
//    }
}
