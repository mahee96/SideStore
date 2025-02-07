//
//  BuildInfo.swift
//  AltStore
//
//  Created by Magesh K on 21/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

public class BuildInfo{
    private static let BUILD_CHANNEL_TAG   = "BuildChannel"     // set by build env, ex CI will set it via env vars, for xcode builds this is empty
    
    private static let MARKETING_VERSION_TAG        = "CFBundleShortVersionString"
    private static let CURRENT_PROJECT_VERSION_TAG  = kCFBundleVersionKey as String
    
    private static let XCODE_VERSION_TAG  = "DTXcode"
    private static let XCODE_REVISION_TAG = "DTXcodeBuild"

    let bundle: Bundle
    
    public init(){
        bundle = Bundle.main
    }
    
    enum BundleError: Swift.Error {
        case invalidURL
    }

    public init(url: URL) throws {
        guard let bundle = Bundle(url: url) else {
            throw BundleError.invalidURL
        }
        self.bundle = bundle
    }
    
    public lazy var channel: ReleaseTracks = {
        let channel  = bundle.object(forInfoDictionaryKey: Self.BUILD_CHANNEL_TAG) as? String
        return ReleaseTracks(rawValue: channel ?? "") ?? .unknown
    }()

    public lazy var project_version: String? = {
        let version  = bundle.object(forInfoDictionaryKey: Self.CURRENT_PROJECT_VERSION_TAG) as? String
        return version
    }()

    public lazy var marketing_version: String? = {
        let version  = bundle.object(forInfoDictionaryKey: Self.MARKETING_VERSION_TAG) as? String
        return version
    }()

    public lazy var xcode: String? = {
        let xcode  = bundle.object(forInfoDictionaryKey: Self.XCODE_VERSION_TAG) as? String
        return xcode
    }()

    public lazy var xcode_revision: String? = {
        let revision  = bundle.object(forInfoDictionaryKey: Self.XCODE_REVISION_TAG) as? String
        return revision
    }()
}
