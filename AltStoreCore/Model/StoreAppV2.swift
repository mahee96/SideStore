//
//  StoreAppV1.swift
//  AltStore
//
//  Created by Magesh K on 21/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData
import SemanticVersion

// added for v0.6.0 appsV2 sources format
@objc(StoreAppV2)
public class StoreAppV2: StoreApp {
    
    //MARK: - properties
    @NSManaged public private(set) var sha256: String?
    @NSManaged public private(set) var revision: String?

    //MARK: - relationships
    @NSManaged @objc(releaseTrack) var releaseTrack: ReleaseTrack?
    
    // overriding
    @nonobjc override public var versions: [AppVersion] {
        var channel: ReleaseTrack.CodingKeys = .stable
        if UserDefaults.standard.isBetaUpdatesEnabled,
           let channelName = UserDefaults.standard.betaUdpatesTrack
        {
            channel = ReleaseTrack.channel(for: channelName)
        }
        return self.releaseTrack?.releasesFor(channel: channel) ?? []
    }
    
    //MARK: - coding keys
    private enum CodingKeys: String, CodingKey
    {
        case sha256
        case channel
        case revision
        case releaseTrack = "releaseChannels"
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
        
        // Now call parent's decode logic to handle its own properties
        try super.decode(from: decoder)

        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
            
            //TODO: V2 sources are required to define channel, hence update from decodeIfPresent() to decode()
            self._channel = try container.decodeIfPresent(String.self, forKey: .channel)
            self.revision = try container.decodeIfPresent(String.self, forKey: .channel)
            
            // Decode and set releaseTrack
            self.releaseTrack = try container.decodeIfPresent(ReleaseTrack.self, forKey: .releaseTrack)
            if versions.isEmpty{
                // get from the StoreApp object itself
                let sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
 
                // draft a new release from existing overriding for new params in v2
                var newRelease = try super.createNewAppVersionIfNotExists(decoder: decoder)

                newRelease = newRelease.mutateForData(channel: channel, sha256: sha256)
                
                try self.setVersions([newRelease])                              // persist this placeholder release
            }else{
                try self.setVersions(versions, persist: {_,_  in })             // just update properties of self, versions are already set in releaseTrack during decoding
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
}

internal extension StoreAppV2{
    @objc override func setVersions(_ versions: [AppVersion], in context: NSManagedObjectContext? = nil) throws {
        var versions = versions
        
        if UserDefaults.standard.isBetaUpdatesEnabled,
           let betaTrack = UserDefaults.standard.betaUdpatesTrack,
           let betaReleases = releaseTrack?.releasesFor(channel: ReleaseTrack.channel(for: betaTrack)),
           let stableReleases = releaseTrack?.releasesFor(channel: .stable),
           let latestBeta = betaReleases.first(where: { $0.isSupported }),
           let latestStable = stableReleases.first(where: { $0.isSupported }),
           let stableSemVer = SemanticVersion(latestStable.version),
           let betaSemVer = SemanticVersion(latestBeta.version),
           betaSemVer > stableSemVer
        {
            versions = betaReleases
        }
        
        // delegate to persist as it was in earlier impl before 0.6.0 but from stable releases only
        try super.setVersions(versions, in: context) { versions, context in
            var releaseTrack = self.releaseTrack
            if releaseTrack == nil && context != nil{
                releaseTrack = ReleaseTrack.makeReleaseTrack(in: context!)
            }
            self.releaseTrack = releaseTrack?.mutateDataFor(stable: versions)
        }
    }
    
    
    override func getLatestSupportedVersion(_ versions: [AppVersion]) -> AppVersion? {
        
        // the one currently in use
        let latestVersion = super.getLatestSupportedVersion(versions)

        if !UserDefaults.standard.isBetaUpdatesEnabled {
            return latestVersion
        }
        
        // since beta updates are enabled, check if we have a latest stable than the beta
        guard let stableReleases = releaseTrack?.releasesFor(channel: .stable),
              let latestStable = super.getLatestSupportedVersion(stableReleases) else
        {
            // need to invoke explicitly again coz this method updates internal fields
            return super.getLatestSupportedVersion(versions)
        }
        
            
        // need to invoke explicitly again coz this method updates internal fields
        return super.getLatestSupportedVersion(versions)
    }
    
}

public extension StoreAppV2{
    
    override func placeholderAppVersion(appVersion: AppVersion, in context: NSManagedObjectContext) -> AppVersion{
        // draft a new release from existing, overriding for new params in v2
        let appVersion = super.placeholderAppVersion(appVersion: appVersion, in: context)
        return appVersion.mutateForData(
            channel: self.channel, // use channel from this v2 store app if available
            revision: self.revision, // use revision from this v2 store app if available
            sha256: self.sha256 // use sha256 from this v2 store app if available
        )
    }
    
    //MARK: - override in subclasses if required
    override class func createStoreApp(in context: NSManagedObjectContext) -> StoreApp{
        return StoreAppV2(context: context)
    }
}
