//
//  StoreAppV1.swift
//  AltStore
//
//  Created by Magesh K on 21/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData
import SemanticVersion

public enum ReleaseTracks: String, CodingKey, CaseIterable
{
    case alpha
    case beta
    case stable
    case unknown
    
        
    public static var betaTracks: [ReleaseTracks] {
        ReleaseTracks.allCases.filter(isBetaTrack)
    }

    public static var nonBetaTracks: [ReleaseTracks] {
        ReleaseTracks.allCases.filter { !isBetaTrack($0) }
    }

    private static func isBetaTrack(_ key: ReleaseTracks) -> Bool {
        key == .alpha || key == .beta
    }
}


// added for v0.6.0 appsV2 sources format
@objc(StoreAppV2)
public class StoreAppV2: StoreApp {
    
    //MARK: - properties
    @NSManaged public private(set) var sha256: String?
    @NSManaged public private(set) var revision: String?

    //MARK: - relationships
    @NSManaged @objc(releaseTracks) private(set) var _releaseTracks: NSOrderedSet?
    
    //MARK: - coding keys
    private enum CodingKeys: String, CodingKey
    {
        case sha256
        case channel
        case revision
        case releaseTracks = "releaseChannels"
    }
    
    public var releaseTracks: [ReleaseTrack]?{
        return _releaseTracks?.array as? [ReleaseTrack]
    }
    
    
    private func releaseTrackFor(track: String) -> ReleaseTrack? {
        return releaseTracks?.first(where: { $0.track == track })
    }
    
    private lazy var stableTrack: ReleaseTrack? = {
        releaseTrackFor(track: ReleaseTracks.stable.stringValue)
    }()
    
    
    private var betaReleases: [AppVersion]? {
        // If beta track is selected, use it instead
        if UserDefaults.standard.isBetaUpdatesEnabled,
           let betaTrack = UserDefaults.standard.betaUdpatesTrack {
            
            // Filter and flatten beta and stable releases
            let betaReleases = releaseTrackFor(track: betaTrack)?.releases?.compactMap { $0 }

            // Ensure both beta and stable releases are found and supported
            if let latestBeta = betaReleases?.first(where: { $0.isSupported }),
               let latestStable = stableTrack?.releases?.first(where: { $0.isSupported }),
               let stableSemVer = SemanticVersion(latestStable.version),
               let betaSemVer = SemanticVersion(latestBeta.version),
               betaSemVer >= stableSemVer
            {
                
                return betaReleases
            }
        }
        return nil
    }
    
    private func getReleases(default releases: ReleaseTrack?) -> [AppVersion]?
    {
        
        return betaReleases ?? releases?.releases?.compactMap { $0 }
    }
    
    @nonobjc override public var versions: [AppVersion] {
        return getReleases(default: stableTrack) ?? []
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
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
            
            //TODO: V2 sources are required to define channel, hence update from decodeIfPresent() to decode()
            self._channel = try container.decodeIfPresent(String.self, forKey: .channel)
            self.revision = try container.decodeIfPresent(String.self, forKey: .revision)
            
            // process parent props
            try self.decode(from: decoder)
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
    
    override func decodeVersions(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode and set releaseTracks (Mandatory for v2 StoreApp)
        let releaseTracks = try container.decode([ReleaseTrack].self, forKey: .releaseTracks)
        self._releaseTracks = NSOrderedSet(array: releaseTracks)
        
        var versions = self.versions
        if versions.isEmpty {
            let sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
            let newRelease = try super.createNewAppVersion(decoder: decoder)
                                       .mutateForData(sha256: sha256, appBundleID: self.bundleIdentifier)
            versions = [newRelease]
        }
        
        try self.setVersions(versions)      // update and persist
    }
}

public extension StoreAppV2{
    
    override class func createStoreApp(in context: NSManagedObjectContext) -> StoreApp{
        return StoreAppV2(context: context)
    }
}
