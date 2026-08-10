//
//  StandaloneExecutionHandler.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
@preconcurrency import AltSign
@preconcurrency import AltStoreCore

protocol AnisetteServerHandler: AnyObject {
    func warnOutdatedAnisetteServer() async throws -> Bool
}

protocol AuthenticationHandler: AnyObject {
    func credentials() async throws -> (String, String)
    func verificationCode() async throws -> String?
    func handleVerificationResult(_ result: Result<(ALTAccount, ALTAppleAPISession, ALTTeam, ALTCertificate?), Error>) async
    
    func resolveTeam(_ teams: [ALTTeam]) async throws -> ALTTeam
    func instructionsViewed() async
    
    func resolveRevocation(certsText: String, teamType: ALTTeamType) async throws -> RevokeDecision
    func resolveResign(mismatchReason: CodeSignValidationReason, context: AuthenticatedOperationContext) async throws -> Bool
    
    func complete() async
}

