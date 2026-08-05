//
//  PipelineRunner.swift
//  AltStore
//
//  Created by Magesh K on 8/3/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
@preconcurrency import WidgetKit
@preconcurrency import AltStoreCore
@preconcurrency import AltSign


protocol PipelineProgress: Sendable{
    func progress(for operation: AppOperation) -> Progress?
    func set(_ progress: Progress?, for operation: AppOperation)
}
protocol PipelineExecutionContext: AnyObject, Sendable {
    var isActivelyManagingAnyApp: Bool { get }
}
protocol PipelineErrorLogger: AnyObject, Sendable {
    func log(_ error: Error, operation: LoggedError.Operation, app: AppProtocol)
    func getMappedError(for operation: AppOperation, error: Error) -> Error
}


// Pipeline based App Operations
final class PipelineRunner: Sendable
{
    let progress: PipelineProgress
    let context: PipelineExecutionContext
    let logger: PipelineErrorLogger
    let defaultEntitlements: [ALTEntitlement: any Sendable]
    
    init(progress: PipelineProgress,
         context: PipelineExecutionContext,
         logger: PipelineErrorLogger,
         defaultEntitlements: [ALTEntitlement: any Sendable] = [:])
    {
        self.progress = progress
        self.context = context
        self.logger = logger
        self.defaultEntitlements = defaultEntitlements
    }
    
    @discardableResult
    func performSingleOperation(_ operation: AppOperation,
                                presentingViewController: UIViewController?,
                                context: AuthenticatedOperationContext = AuthenticatedOperationContext(),
                                completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> RefreshGroup
    {
        let group = RefreshGroup(context: context)
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw group.context.error ?? OperationError.unknown() }
                let installedApp = try result.get()
                completionHandler(.success(installedApp))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        debugLog("[AppManager] performSingleOperation started for: \(operation.bundleIdentifier)")
        group.activeTask = Task.detached {
            do {
                debugLog("[AppManager] performSingleOperation executing task for: \(operation.bundleIdentifier)")
                try await self.perform([operation], presentingViewController: presentingViewController, group: group)
            } catch {
                debugLog("[AppManager] performSingleOperation task failed for: \(operation.bundleIdentifier) with error: \(error)")
                completionHandler(.failure(error))
            }
        }
        
        return group
    }
    
    func performVoidOperation(_ operation: AppOperation,
                                      presentingViewController: UIViewController?,
                                      completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        self.performSingleOperation(operation, presentingViewController: presentingViewController) { (result) in
            switch result {
            case .success:
                completionHandler(.success(()))
            case .failure(let error):
                completionHandler(.failure(error))
            }
        }
    }
    
    @discardableResult
    func perform(_ operations: [AppOperation],
                         presentingViewController: UIViewController?,
                         group: RefreshGroup) async throws -> RefreshGroup
    {
        let operations = operations.filter { progress.progress(for: $0) == nil || progress.progress(for: $0)?.isCancelled == true }
        guard !operations.isEmpty else { throw OperationError.cancelled }
        
        let backgroundTaskID = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "com.altstore.AppManager.perform") {
                // Expired
            }
        }
        
        // Disable the idleTimeout
        await MainActor.run {
            if !UIApplication.shared.isIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = UserDefaults.standard.isIdleTimeoutDisableEnabled
            }
        }
        
        if group.context.dbBackgroundContext == nil {
            // create a background core-data managedObject context
            group.context.dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        }
        
        defer {
            group.context.dbBackgroundContext = nil         // Clean up pipeline database context
            for operation in operations {                   // Clean up progress for all operations
                progress.set(nil, for: operation)
            }
            if let error = group.context.error {            // Mark error as-is
                for operation in operations {
                    group.set(.failure(error), forAppWithBundleIdentifier: operation.bundleIdentifier)
                }
            }
            
            
            // Re-enable idleTimeout if no more actions are running and end background task
            Task { @MainActor in
                if UIApplication.shared.isIdleTimerDisabled && !context.isActivelyManagingAnyApp {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
        }
        
        try await Task.detached {
            /* Minimuxer Readiness Check */
            if let minimuxerError = await getMinimuxerStatus().operationError {
                group.context.error = minimuxerError
                throw minimuxerError
            }
            
            group.progress.completedUnitCount = 1
            
            for operation in operations
            {
                let progress = Progress.discreteProgress(totalUnitCount: 100)
                self.progress.set(progress, for: operation)
                group.progress.addChild(progress, withPendingUnitCount: 100 / Int64(operations.count))
            }
            
            // take whatever it is - valid or nil, both works
            group.context.presentingViewController = presentingViewController
            
            /* Authenticate (if necessary) */
            if group.context.session == nil
            {
                do {
                    let (team, cert, session) = try await AuthManager.shared.performAuthenticationOperation(
                        context: group.context,
                        presentingViewController: presentingViewController,
                        skipDeviceRegistration: false
                    )
                    group.context.team = team
                    group.context.signingCertificate = cert
                    group.context.session = session
                } catch {
                    group.context.error = error
                    throw error
                }
            }
            
            /* Preflight SideStore specific validations */
            let unhandledOperations = operations.filter { operation in
                let isSideStore = (operation.app as? ALTApplication)?.isAltStoreApp == true                 ||
                operation.bundleIdentifier.contains(ALTApplication.altstoreBundleID)     ||
                operation.bundleIdentifier == StoreApp.altstoreAppID
                
                if isSideStore {
                    return presentingViewController is ResignAltStoreViewController
                }
                return true
            }
            
            do {
                let validateOp = try PreflightChecksOperation(
                    operations: unhandledOperations,
                    presentingViewController: presentingViewController,
                    context: group.context
                )
                try await validateOp.execute()
            } catch {
                group.context.error = error
                throw error
            }
            
            
            // run the operation pipeline
            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                for operation in operations {
                    taskGroup.addTask {
                        try await self.performOperation(for: operation, group: group)
                    }
                }
                while let _ = try await taskGroup.next() {}
            }
            await MainActor.run {
                group.completionHandler?(group.results)
            }
        }.value
        
        return group
    }
    
    func performOperation(for operation: AppOperation, group: RefreshGroup) async throws {
        debugLog("[AppManager] performOperation: Starting execution for app: \(operation.bundleIdentifier)")
        defer{
            // request update view context's in-mem coredata caches (coz we worked so far on bg context)
            DatabaseManager.shared.viewContext.performAndWait {
                DatabaseManager.shared.viewContext.processPendingChanges()
            }
        }
        do {
            let result = try await self.performPipeline(for: operation, group: group)
            progress.set(nil, for: operation)
            debugLog("[AppManager] performOperation: completed successfully. progress was reset for installedApp: \(result.bundleIdentifier)")
            
            // persist the result
            if let context = result.managedObjectContext {
                do {
                    try context.performAndWait {
                        let hasChanges = context.hasChanges
                        if hasChanges {
                            try context.save()
                        }
                        debugLog("[AppManager] performOperation: Context changes were saved for installedApp: \(result.bundleIdentifier)")
                    }
                } catch {
                    debugLog("[AppManager] perform(): Failed to save InstalledApp to database. \(error.localizedDescription)")
                }
            }
            
            group.set(.success(result), forAppWithBundleIdentifier: result.bundleIdentifier)
            debugLog("[AppManager] performOperation: Execution SUCCESS for app: \(operation.bundleIdentifier)")
            
            debugLog("[AppManager] performOperation: Reloading widget timelines...")
            WidgetCenter.shared.reloadAllTimelines()
            debugLog("[AppManager] performOperation: Reloading COMPLETE for widget timelines.")
            
            if result.bundleIdentifier == StoreApp.altstoreAppID {
                let context = StandaloneOperationContext(steps: .scheduleExpirationWarningNotification, dbBackgroundContext: group.context.dbBackgroundContext)
                let scheduleNotifOp = try ScheduleExpirationWarningNotificationOperation(
                    installedApp: result,
                    context: context
                )
                try await scheduleNotifOp.execute()
            }
        } catch {
            progress.set(nil, for: operation)
            
            if Task.isCancelled {
                debugLog("[AppManager] performOperation: Execution CANCELLED for app: \(operation.bundleIdentifier)")
            } else {
                debugLog("[AppManager] performOperation: Execution FAILED for app: \(operation.bundleIdentifier) with error: \(error.localizedDescription)")
            }
            
            let mappedError = logger.getMappedError(for: operation, error: error)
            
            logger.log(error, operation: operation.loggedErrorOperation, app: operation.app)
            
            group.set(.failure(mappedError), forAppWithBundleIdentifier: operation.bundleIdentifier)
        }
    }
    
    private func performPipeline(for operation: AppOperation, group: RefreshGroup) async throws -> InstalledApp
    {
        let pipelineSteps = PipelineStepDefinition.steps(for: operation)
        let context = InstallAppOperationContext(
            pipelineSteps: pipelineSteps,
            bundleIdentifier: operation.bundleIdentifier,
            authenticatedContext: group.context,
            additionalEntitlements: defaultEntitlements,
        )
        
        if case .install(_, let customID) = operation { context.customBundleIdentifier  = customID }
        if case .update(_,  let customID) = operation { context.customBundleIdentifier  = customID }
        if case .resign(_,  let mode)     = operation { context.alternateIconMode       = mode }
        
        if let app = operation.app as? InstalledApp {
            context.targetAppBundle = ALTApplication(fileURL: app.fileURL)
            context.useMainProfile = app.useMainProfile
            context.customBundleIdentifier = app.customBundleIdentifier
            context.installedApp = app
        }
        
        context.beginInstallationHandler = { (installedApp) in
            group.beginInstallationHandler?(installedApp)
        }
        
        var downloadingApp = operation.app
        if let installedApp = operation.app as? InstalledApp {
            if case .resign = operation { downloadingApp = installedApp }
            else if let storeApp = installedApp.storeApp, !FileManager.default.fileExists(atPath: installedApp.fileURL.path) {
                downloadingApp = storeApp
            }
        }
        
        let permissionReviewMode: VerifyAppOperation.PermissionReviewMode
        switch operation {
        case .install: permissionReviewMode = .all
        case .update: permissionReviewMode = .added
        default: permissionReviewMode = .none
        }
        let permissionsMode = UserDefaults.shared.permissionCheckingDisabled ? .none : permissionReviewMode
        let operationProgress = progress.progress(for: operation)
        return try await PipelineExecutor.shared.executePipeline(
            steps: pipelineSteps,
            context: context,
            operation: operation,
            group: group,
            downloadingApp: downloadingApp,
            permissionsMode: permissionsMode,
            operationProgress: operationProgress
        )
    }
}


