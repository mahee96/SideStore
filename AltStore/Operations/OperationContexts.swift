//
//  Contexts.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import CoreData
import Network
@preconcurrency import AltStoreCore
@preconcurrency import AltSign


enum AlternateIconMode {
    case preserve
    case set(URL)
    case remove
}

protocol WeightedOperationContext: AnyObject {
    func weight(for operationType: Any.Type) -> Int64?
}

class OperationContext
{
    var error: Error?
    var presentingViewController: UIViewController?
    var dbBackgroundContext: NSManagedObjectContext?

    fileprivate init(error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        self.error = error
        self.presentingViewController = presentingViewController
        self.dbBackgroundContext = dbBackgroundContext
    }

    fileprivate init(context: OperationContext)
    {
        self.error = context.error
        self.presentingViewController = context.presentingViewController
        self.dbBackgroundContext = context.dbBackgroundContext
    }
}

class StandaloneOperationContext: OperationContext, WeightedOperationContext
{
    let steps: [StandaloneExecutionStep]

    init(steps: [StandaloneExecutionStep], error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        self.steps = steps
        super.init(error: error, presentingViewController: presentingViewController, dbBackgroundContext: dbBackgroundContext)
    }

    init(context: StandaloneOperationContext)
    {
        self.steps = context.steps
        super.init(context: context)
    }

    func weight(for operationType: Any.Type) -> Int64? {
        guard let step = StandaloneStep.step(for: operationType), step != .unknown else { return nil }
        return steps.first(where: { $0.step == step })?.weight
    }
}

class CachedOperationContext: OperationContext
{
    var appIDs: [ALTAppID]?
    var appGroups: [ALTAppGroup]?

    override init(error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        super.init(error: error, presentingViewController: presentingViewController, dbBackgroundContext: dbBackgroundContext)
    }

    override init(context: OperationContext)
    {
        super.init(context: context)
    }

    init(context: CachedOperationContext) {
        super.init(context: context)
        self.appIDs = context.appIDs
        self.appGroups = context.appGroups
    }
}

final class AuthenticatedOperationContext: CachedOperationContext, WeightedOperationContext
{
    var session: ALTAppleAPISession?
    var team: ALTTeam?
    var certificate: ALTCertificate?
    var activeCertificates: [ALTCertificate]?
    
    var isSideStoreResignDismissed: Bool = false

    let steps: [StandaloneExecutionStep]

    override init(error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        self.steps = .authenticate
        super.init(error: error, presentingViewController: presentingViewController, dbBackgroundContext: dbBackgroundContext)
    }

    init(context: AuthenticatedOperationContext) {
        self.steps = context.steps
        super.init(context: context)
        self.session = context.session
        self.team = context.team
        self.certificate = context.certificate
        self.activeCertificates = context.activeCertificates
        self.isSideStoreResignDismissed = context.isSideStoreResignDismissed
    }

    func weight(for operationType: Any.Type) -> Int64? {
        guard let step = StandaloneStep.step(for: operationType), step != .unknown else { return nil }
        return steps.first(where: { $0.step == step })?.weight
    }
}

class PipelineOperationContext: OperationContext, WeightedOperationContext
{
    let pipelineSteps: [PipelineExecutionStep]

    init(pipelineSteps: [PipelineExecutionStep], error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        self.pipelineSteps = pipelineSteps
        super.init(error: error, presentingViewController: presentingViewController, dbBackgroundContext: dbBackgroundContext)
    }

    init(context: PipelineOperationContext)
    {
        self.pipelineSteps = context.pipelineSteps
        super.init(context: context)
    }

    func weight(for operationType: Any.Type) -> Int64? {
        guard let step = PipelineStep.step(for: operationType) else { return nil }
        return pipelineSteps.first(where: { $0.step == step })?.weight
    }
}

@dynamicMemberLookup
class AppOperationContext: PipelineOperationContext
{
    let bundleIdentifier: String
    var customBundleIdentifier: String?
    var app: ALTApplication?
    var provisioningProfiles: [String: ALTProvisioningProfile]?
    var appexBundleIds: [String: String]?
    var useMainProfile = false
    var isFinished = false

    let authenticatedContext: AuthenticatedOperationContext

    var targetBundleIdentifier: String { customBundleIdentifier ?? bundleIdentifier }

    override var error: Error? {
        get { _error ?? authenticatedContext.error }
        set { _error = newValue
            if authenticatedContext.error == nil
            {
                // Assign newValue to authenticatedContext.error if the latter is nil.
                // This fixes some operations continuing even after an error has occured.
                authenticatedContext.error = newValue
            }
        }
    }
    private var _error: Error?

    init(pipelineSteps: [PipelineExecutionStep], bundleIdentifier: String, authenticatedContext: AuthenticatedOperationContext)
    {
        self.bundleIdentifier = bundleIdentifier
        self.authenticatedContext = authenticatedContext
        super.init(
            pipelineSteps: pipelineSteps,
            error: nil,
            presentingViewController: authenticatedContext.presentingViewController,
            dbBackgroundContext: authenticatedContext.dbBackgroundContext
        )
    }

    subscript<T>(dynamicMember keyPath: WritableKeyPath<AuthenticatedOperationContext, T>) -> T
    {
        return self.authenticatedContext[keyPath: keyPath]
    }
}

class InstallAppOperationContext: AppOperationContext
{
    lazy var temporaryDirectory: URL = {
        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        }
        catch { self.error = error }
        return temporaryDirectory
    }()

    var ipaURL: URL?
    var resignedApp: ALTApplication?
    var installedApp: InstalledApp?
    
    var beginInstallationHandler: ((InstalledApp) -> Void)?

    var alternateIconMode: AlternateIconMode = .preserve

    var alternateIconURL: URL? {
        switch self.alternateIconMode {
        case .set(let url):
            return url
        case .preserve:
            if let installedApp = self.installedApp, installedApp.hasAlternateIcon {
                return installedApp.alternateIconURL
            }
            return nil
        case .remove:
            return nil
        }
    }

    var shouldTurnOffData: Bool = false

    // Non-nil when installing from a source.
    @AsyncManaged
    var appVersion: AppVersion?
}
