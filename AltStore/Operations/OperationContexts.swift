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

fileprivate struct OperationStepItem {
    let step: any OperationStep
    let weight: Int64
}

protocol WeightedOperationContext: AnyObject {
    func weightForFirstOccurrence(of step: some OperationStep) -> Int64?
    func weight(for step: some OperationStep, occurrenceNumber: Int) -> Int64?
    func consumeWeight(for step: some OperationStep) -> Int64?
}

class OperationContext: WeightedOperationContext
{
    var error: Error?
    var presentingViewController: UIViewController?
    var dbBackgroundContext: NSManagedObjectContext?

    fileprivate var stepItems: [OperationStepItem]
    fileprivate var currentIndex = 0

    fileprivate init(stepItems: [OperationStepItem] = [], error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        self.stepItems = stepItems
        self.error = error
        self.presentingViewController = presentingViewController
        self.dbBackgroundContext = dbBackgroundContext
    }

    fileprivate init(context: OperationContext)
    {
        self.stepItems = context.stepItems
        self.currentIndex = context.currentIndex
        self.error = context.error
        self.presentingViewController = context.presentingViewController
        self.dbBackgroundContext = context.dbBackgroundContext
    }

    func weightForFirstOccurrence(of step: some OperationStep) -> Int64? {
        weight(for: step, occurrenceNumber: 1)
    }

    func weight(for step: some OperationStep, occurrenceNumber: Int) -> Int64? {
        guard let target = (step as Any) as? AnyHashable else {
            debugLog("[OperationContext] Failed to cast step '\(step)' to AnyHashable")
            return nil
        }
        var matchCount = 0
        for item in stepItems {
            if let itemTarget = (item.step as Any) as? AnyHashable, itemTarget == target {
                matchCount += 1
                if matchCount == occurrenceNumber {
                    return item.weight
                }
            }
        }
        verboseLog("[OperationContext] Weight not found for step '\(step)' (occurrence \(occurrenceNumber))")
        return nil
    }

    func consumeWeight(for step: some OperationStep) -> Int64? {
        guard let target = (step as Any) as? AnyHashable else {
            debugLog("[OperationContext] Failed to cast step '\(step)' to AnyHashable during consumeWeight")
            return nil
        }
        guard let index = stepItems.indices[currentIndex...].first(where: {
            guard let itemTarget = (stepItems[$0].step as Any) as? AnyHashable else { return false }
            return itemTarget == target
        }) else {
            debugLog("[OperationContext] Failed to consume weight for step '\(step)' from index \(currentIndex)")
            return nil
        }
        currentIndex = index + 1
        return stepItems[index].weight
    }
}

class StandaloneOperationContext: OperationContext
{
    let steps: [StandaloneExecutionStep]

    init(steps: [StandaloneExecutionStep], error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        self.steps = steps
        super.init(stepItems: steps.map { OperationStepItem(step: $0.step, weight: $0.weight) }, error: error, presentingViewController: presentingViewController, dbBackgroundContext: dbBackgroundContext)
    }

    init(context: StandaloneOperationContext)
    {
        self.steps = context.steps
        super.init(context: context)
    }
}

class CachedOperationContext: StandaloneOperationContext
{
    var appIDs: [ALTAppID]?
    var appGroups: [ALTAppGroup]?

    override init(steps: [StandaloneExecutionStep] = [], error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        super.init(steps: steps, error: error, presentingViewController: presentingViewController, dbBackgroundContext: dbBackgroundContext)
    }

    override init(context: StandaloneOperationContext)
    {
        super.init(context: context)
    }

    init(context: CachedOperationContext) {
        self.appIDs = context.appIDs
        self.appGroups = context.appGroups
        super.init(context: context)
    }
}

final class AuthenticatedOperationContext: CachedOperationContext
{
    var session: ALTAppleAPISession?
    var team: ALTTeam?
    var certificate: ALTCertificate?
    var activeCertificates: [ALTCertificate]?
    
    var isSideStoreResignDismissed: Bool = false

    init(error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        super.init(steps: .authenticate, error: error, presentingViewController: presentingViewController, dbBackgroundContext: dbBackgroundContext)
    }

    init(context: AuthenticatedOperationContext) {
        super.init(context: context)
        self.session = context.session
        self.team = context.team
        self.certificate = context.certificate
        self.activeCertificates = context.activeCertificates
        self.isSideStoreResignDismissed = context.isSideStoreResignDismissed
    }
}

class PipelineOperationContext: OperationContext
{
    let pipelineSteps: [PipelineExecutionStep]

    init(pipelineSteps: [PipelineExecutionStep], error: Error? = nil, presentingViewController: UIViewController? = nil, dbBackgroundContext: NSManagedObjectContext? = nil)
    {
        self.pipelineSteps = pipelineSteps
        super.init(stepItems: pipelineSteps.map { OperationStepItem(step: $0.step, weight: $0.weight) }, error: error, presentingViewController: presentingViewController, dbBackgroundContext: dbBackgroundContext)
    }

    init(context: PipelineOperationContext)
    {
        self.pipelineSteps = context.pipelineSteps
        super.init(context: context)
    }
}

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
    var overrideCertificate: ALTCertificate?

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
