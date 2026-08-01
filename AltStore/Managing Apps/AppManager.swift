//
//  AppManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
@preconcurrency import UIKit
import UserNotifications
import MobileCoreServices
import Intents
import Combine
import WidgetKit
@preconcurrency import AltStoreCore
@preconcurrency import AltSign
import UniformTypeIdentifiers

extension AppManager
{
    static let didFetchSourceNotification = Notification.Name("io.sidestore.AppManager.didFetchSource")
    static let didAddSourceNotification = Notification.Name("io.sidestore.AppManager.didAddSource")
    static let didRemoveSourceNotification = Notification.Name("io.sidestore.AppManager.didRemoveSource")
    static let willInstallAppFromNewSourceNotification = Notification.Name("io.sidestore.AppManager.willInstallAppFromNewSource")
    
    static let expirationWarningNotificationID = "sidestore-expiration-warning"
    static let enableJITResultNotificationID = "sidestore-enable-jit"
}

@available(iOS 13, *)
final class AppManagerPublisher: ObservableObject
{
    @Published
    fileprivate(set) var installationProgress = [String: Progress]()
    
    @Published
    fileprivate(set) var refreshProgress = [String: Progress]()
}

class AppManager: ObservableObject
{
    static let shared = AppManager()

    private static let restartLock = NSLock()
    
    private(set) var updatePatronsResult: Result<Void, Error>?
    
    @Published
    private(set) var updateSourcesResult: Result<Void, Error>? // nil == loading
    
    private let operationQueue = OperationQueue()
    private let serialOperationQueue = OperationQueue()
    
    @Published private var installationProgress = [String: Progress]()
    @Published private var refreshProgress = [String: Progress]()
    private var cancellables: Set<AnyCancellable> = []
    
    private let progressLock = NSLock()
    
    private init()
    {
        self.operationQueue.name = "com.altstore.AppManager.operationQueue"
        
        self.serialOperationQueue.name = "com.altstore.AppManager.serialOperationQueue"
        self.serialOperationQueue.maxConcurrentOperationCount = 1
        
        self.prepareSubscriptions()
    }
    
    func prepareSubscriptions()
    {
        /// Every time refreshProgress is changed, update all InstalledApps in memory
        /// so that app.isRefreshing == refreshProgress.keys.contains(app.bundleID)
        
        self.$refreshProgress
            .receive(on: RunLoop.main)
            .map(\.keys)
            .flatMap { (bundleIDs) in
                DatabaseManager.shared.viewContext.registeredObjects.publisher
                    .compactMap { $0 as? InstalledApp }
                    .map { ($0, bundleIDs.contains($0.bundleIdentifier)) }
            }
            .sink { (installedApp, isRefreshing) in
                if installedApp.isRefreshing != isRefreshing {
                    installedApp.isRefreshing = isRefreshing
                }
            }
            .store(in: &self.cancellables)
    }
}

extension AppManager
{
    func reconcileInstalledApps() async
    {
        await Task.detached {
            let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            var altstoreAppObjectID: NSManagedObjectID?
    
            #if targetEnvironment(simulator)
            // Apps aren't ever actually installed to simulator, so just do nothing rather than delete them from database.
            #else
        
            do
            {
                try await dbBackgroundContext.perform {
                    let installedApps = InstalledApp.all(in: dbBackgroundContext)
                
                    if UserDefaults.standard.legacySideloadedApps == nil
                    {
                        // First time updating apps since updating AltStore to use custom UTIs,
                        // so cache all existing apps temporarily to prevent us from accidentally
                        // deleting them due to their custom UTI not existing (yet).
                        let apps = installedApps.map { $0.bundleIdentifier }
                        UserDefaults.standard.legacySideloadedApps = apps
                    }
                
                    let legacySideloadedApps = Set(UserDefaults.standard.legacySideloadedApps ?? [])
                
                    for app in installedApps
                    {
                        guard app.bundleIdentifier != StoreApp.altstoreAppID else {
                            altstoreAppObjectID = app.objectID
                            continue
                        }
                    
                        guard !self.isActivelyManagingApp(withBundleID: app.bundleIdentifier) else { continue }
                    
                        if !UserDefaults.standard.isLegacyDeactivationSupported
                        {
                            // We can't (ab)use provisioning profiles to deactivate apps,
                            // which means we must delete apps to free up active slots.
                            // So, only check if active apps are installed to prevent
                            // false positives when checking inactive apps.
                            guard app.isActive else { continue }
                        }
                    
                        let uti = UTTypeCopyDeclaration(app.installedAppUTI as CFString)?.takeRetainedValue() as NSDictionary?
                        if uti == nil && !legacySideloadedApps.contains(app.bundleIdentifier)
                        {
                            // This UTI is not declared by any apps, which means this app has been deleted by the user.
                            // This app is also not a legacy sideloaded app, so we can assume it's fine to delete it.
                            dbBackgroundContext.delete(app)
                        
                            if var patchedApps = UserDefaults.standard.patchedApps, let index = patchedApps.firstIndex(of: app.bundleIdentifier)
                            {
                                patchedApps.remove(at: index)
                                UserDefaults.standard.patchedApps = patchedApps
                            }
                        }
                    }
                
                    if dbBackgroundContext.hasChanges {
                        try dbBackgroundContext.save()
                    }
                }
            
                if let objectID = altstoreAppObjectID {
                    let context = StandaloneOperationContext(steps: .scheduleExpirationWarningNotification, dbBackgroundContext: dbBackgroundContext)
                    let app = await dbBackgroundContext.perform {
                        dbBackgroundContext.object(with: objectID) as! InstalledApp
                    }
                    let scheduleNotifOp = try ScheduleExpirationWarningNotificationOperation(
                        installedApp: app,
                        context: context
                    )
                    try await scheduleNotifOp.execute()
                }
            }
            catch
            {
                debugLog("Error while fetching installed apps. \(error)")
            }
            #endif
        
            do
            {
                let installedAppBundleIDs = await dbBackgroundContext.perform {
                    InstalledApp.all(in: dbBackgroundContext).map { $0.bundleIdentifier }
                }
                            
                let cachedAppDirectories = try FileManager.default.contentsOfDirectory(at: InstalledApp.appsDirectoryURL,
                                                                                       includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                                                                                       options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
                for appDirectory in cachedAppDirectories
                {
                    do
                    {
                        let resourceValues = try appDirectory.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                        guard let isDirectory = resourceValues.isDirectory, let bundleID = resourceValues.name else { continue }
                    
                        if isDirectory && !installedAppBundleIDs.contains(bundleID) && !self.isActivelyManagingApp(withBundleID: bundleID)
                        {
                            debugLog("DELETING CACHED APP: \(bundleID)")
                            try FileManager.default.removeItem(at: appDirectory)
                        }
                    }
                    catch
                    {
                        debugLog("Failed to remove cached app directory. \(error)")
                    }
                }
            }
            catch
            {
                debugLog("Failed to remove cached apps. \(error)")
            }
    
        }.value
    }
    
    func authenticate(presentingViewController: UIViewController?,
                      skipDeviceRegistration: Bool = true,
                      skipCertificateProvisioning: Bool = false,
                      completionHandler: @escaping (Result<(ALTTeam, ALTCertificate?, ALTAppleAPISession), Error>) -> Void)
    {
        let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let context = AuthenticatedOperationContext(
            presentingViewController: presentingViewController,
            dbBackgroundContext: dbBackgroundContext
        )
        
        Task {
            do {
                let authenticationOperation = try AuthenticationOperation(
                    context: context,
                    presentingViewController: presentingViewController,
                    skipDeviceRegistration: skipDeviceRegistration,
                    skipCertificateProvisioning: skipCertificateProvisioning
                )
                let result = try await authenticationOperation.execute()
                completionHandler(.success(result))
            } catch {
                context.error = error
                completionHandler(.failure(error))
            }
        }
    }
    
    func deactivateApps(for app: ALTApplication, presentingViewController: UIViewController?, completion: @escaping (Result<Void, Error>) -> Void)
    {
        guard !UserDefaults.standard.isAppLimitDisabled, let activeAppsLimit = UserDefaults.standard.activeAppsLimit else { return completion(.success(())) }
        
        DispatchQueue.main.async {
            // Only apps signed with a free developer certificate count toward the 3-app free account limit.
            // Apps signed with a paid certificate coexist independently and must not be counted here.
            let activeApps = InstalledApp.fetchActiveApps(in: DatabaseManager.shared.viewContext)
                .filter { $0.bundleIdentifier != app.bundleIdentifier } // Don't count app towards total if it matches activating app
                .filter { ($0.team?.type ?? .unknown) == .free }        // Only free-cert-signed apps count against the free limit
                .sorted { ($0.name, $0.refreshedDate) < ($1.name, $1.refreshedDate) }
            
            var title: String = NSLocalizedString("Cannot Activate More than 3 Apps", comment: "")
            let message: String
            
            if UserDefaults.standard.activeAppLimitIncludesExtensions
            {
                if app.appExtensions.isEmpty
                {
                    message = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions. Please choose an app to deactivate.", comment: "")
                }
                else
                {
                    title = NSLocalizedString("Cannot Activate More than 3 Apps and App Extensions", comment: "")
                    
                    let appExtensionText = app.appExtensions.count == 1 ? NSLocalizedString("app extension", comment: "") : NSLocalizedString("app extensions", comment: "")
                    message = String(format: NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions, and \"%@\" contains %@ %@. Please choose an app to deactivate.", comment: ""), app.name, NSNumber(value: app.appExtensions.count), appExtensionText)
                }
            }
            else
            {
                message = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps. Please choose an app to deactivate.", comment: "")
            }
            
            let activeAppsCount = activeApps.map { $0.requiredActiveSlots }.reduce(0, +)
                    
            let availableActiveApps = max(activeAppsLimit - activeAppsCount, 0)
            let requiredActiveSlots = UserDefaults.standard.activeAppLimitIncludesExtensions ? (1 + app.appExtensions.count) : 1
            guard requiredActiveSlots > availableActiveApps else { return completion(.success(())) }

            guard let presentingViewController else {
                let failureReason = String(format: NSLocalizedString("SideStore needs to deactivate another app before installing %@.", comment: ""), app.name)
                return completion(.failure(OperationError.forbidden(failureReason: failureReason)))
            }
            
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { (action) in
                completion(.failure(OperationError.cancelled))
            })
            
            for activeApp in activeApps where activeApp.bundleIdentifier != StoreApp.altstoreAppID
            {
                alertController.addAction(UIAlertAction(title: activeApp.name, style: .default) { (action) in
                    activeApp.isActive = false
                                    
                    self.deactivate(activeApp, presentingViewController: presentingViewController) { (result) in
                        switch result
                        {
                        case .failure(let error):
                            activeApp.managedObjectContext?.perform {
                                activeApp.isActive = true
                                completion(.failure(error))
                            }
                            
                        case .success:
                            self.deactivateApps(for: app, presentingViewController: presentingViewController, completion: completion)
                        }
                    }
                })
            }
            
            presentingViewController.present(alertController, animated: true, completion: nil)
        }
    }
    
    func clearAppCache(completion: @escaping (Result<Void, Error>) -> Void)
    {
        Task.detached {
            do {
                let context = StandaloneOperationContext(steps: .clearAppCache)
                try await ClearAppCacheOperation(context: context).execute()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func log(_ error: Error, operation: LoggedError.Operation, app: AppProtocol)
    {
        switch error
        {
            case is CancellationError: return // Don't log CancellationErrors
            case let nsError as NSError where nsError.domain == CancellationError()._domain: return
            default: break
        }

        // Sanitize NSError on same thread before performing background task.
        let sanitizedError = (error as NSError).sanitizedForSerialization()

        DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            var app = app
            if let managedApp = app as? NSManagedObject, let tempApp = context.object(with: managedApp.objectID) as? AppProtocol
            {
                app = tempApp
            }

            do
            {
                LoggedError(error: sanitizedError, app: app, operation: operation, context: context)
                debugLog("AppManager.log(): error:\(sanitizedError) app:\(app.bundleIdentifier) operation:\(operation)")
                try context.save()
            }
            catch let saveError
            {
                debugLog("[ALTLog] Failed to log error \(sanitizedError.domain) code \(sanitizedError.code) for \(app.bundleIdentifier): \(saveError)")
            }
        }
    }

}

extension AppManager
{
    func fetchSource(sourceURL: URL, managedObjectContext: NSManagedObjectContext) async throws -> Source
    {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try fetchSource(sourceURL: sourceURL, managedObjectContext: managedObjectContext) { result in
                    continuation.resume(with: result)
                }
            }catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func fetchSources() async throws -> (Set<Source>, NSManagedObjectContext)
    {
        try await withCheckedThrowingContinuation { continuation in
            fetchSources { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func add(@AsyncManaged _ source: Source,
             message: String? = NSLocalizedString("Make sure to only add sources that you trust.", comment: ""),
             presentingViewController: UIViewController) async throws
    {
        let (sourceName, sourceURL) = await $source.perform { ($0.name, $0.sourceURL) }
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        async let fetchedSource = try await self.fetchSource(sourceURL: sourceURL, managedObjectContext: context) // Fetch source async while showing alert.

        let title = String(format: NSLocalizedString("Would you like to add the source “%@”?", comment: ""), sourceName)
        let action = await UIAlertAction(title: NSLocalizedString("Add Source", comment: ""), style: .default)
        try await presentingViewController.presentConfirmationAlert(title: title, message: message ?? "", primaryAction: action)

        // Wait for fetch to finish before saving context to make
        // sure there isn't already a source with this identifier.
        let sourceExists = try await fetchedSource.isAdded
        
        // This is just a sanity check, so pass nil for existingSource to keep code simple.
        guard !sourceExists else { throw SourceError.duplicate(source, existingSource: nil) }
        
        try await context.performAsync {
            try context.save()
        }
        
        NotificationCenter.default.post(name: AppManager.didAddSourceNotification, object: source)
    }
    
    func remove(@AsyncManaged _ source: Source, presentingViewController: UIViewController) async throws
    {
        let (sourceName, sourceID) = await $source.perform { ($0.name, $0.identifier) }
        guard sourceID != Source.altStoreIdentifier else {
            throw OperationError.forbidden(failureReason: NSLocalizedString("The default SideStore source cannot be removed.", comment: ""))
        }
        
        let title = String(format: NSLocalizedString("Are you sure you want to remove the source “%@”?", comment: ""), sourceName)
        let message = NSLocalizedString("Any apps you've installed from this source will remain, but they'll no longer receive any app updates.", comment: "")
        let action = await UIAlertAction(title: NSLocalizedString("Remove Source", comment: ""), style: .destructive)
        try await presentingViewController.presentConfirmationAlert(title: title, message: message, primaryAction: action)
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        try await context.performAsync {
            let predicate = NSPredicate(format: "%K == %@", #keyPath(Source.identifier), sourceID)
            guard let source = Source.first(satisfying: predicate, in: context) else { return } // Doesn't exist == success.
            
            context.delete(source)
            try context.save()
        }
        
        NotificationCenter.default.post(name: AppManager.didRemoveSourceNotification, object: source)
    }
    
    @discardableResult
    func installAsync<T: AppProtocol>(@AsyncManaged _ app: T, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext(),
                                      completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) async -> RefreshGroup
    {
        @AsyncManaged var installingApp: AppProtocol = app
        var didAddSource = false
        
        do
        {
            // Check if we need to add source first before installing app.
            if let source = await $app.perform({ $0.storeApp?.source }), try await !source.isAdded
            {
                // This app's source is not yet added, so add it first.
                guard let presentingViewController else { throw OperationError.sourceNotAdded(source) }
                
                let (appName, appBundleID, sourceID) = await $app.perform { ($0.name, $0.bundleIdentifier, source.identifier) }
                
                do
                {
                    let message = String(format: NSLocalizedString("You must add this source before installing apps from it.\n\n“%@” will begin downloading once it has been added.", comment: ""), appName)
                    try await AppManager.shared.add(source, message: message, presentingViewController: presentingViewController)
                }
                catch let error as CancellationError 
                {
                    throw error
                }
                catch
                {
                    // This should be an alert, so show directly rather than re-throwing error.
                    await presentingViewController.presentAlert(title: NSLocalizedString("Unable to Add Source", comment: ""), message: error.localizedDescription)
                    
                    // Don't rethrow error
                    // throw error
                    
                    throw CancellationError()
                }
                
                // Fetch persisted StoreApp to use for remainder of operation.
                installingApp = try await DatabaseManager.shared.viewContext.performAsync {
                    let fetchRequest = StoreApp.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                                         #keyPath(StoreApp.bundleIdentifier), appBundleID,
                                                         #keyPath(StoreApp.sourceIdentifier), sourceID)
                    
                    guard let storeApp = try DatabaseManager.shared.viewContext.fetch(fetchRequest).first else { throw OperationError.appNotFound(name: appName) }
                    return storeApp
                }
                
                didAddSource = true
            }
        }
        catch
        {
            completionHandler(.failure(error))
            
            let group = RefreshGroup(context: context)
            group.progress.cancel()
            return group
        }
        
        let group = await $installingApp.perform { self.install($0, presentingViewController: presentingViewController, context: context, completionHandler: completionHandler) }
        
        if didAddSource
        {
            // Post notification from main queue _after_ assigning progress for it
            await MainActor.run { [installingApp] in
                NotificationCenter.default.post(name: AppManager.willInstallAppFromNewSourceNotification, object: installingApp)
            }
        }
        
        return group
    }
    
    @discardableResult
    func fetchSource(sourceURL: URL,
                     managedObjectContext: NSManagedObjectContext,
                     completionHandler: @escaping (Result<Source, Error>) -> Void) throws -> FetchSourceOperation
    {
        let context = StandaloneOperationContext(steps: [], dbBackgroundContext: managedObjectContext)
        let fetchSourceOperation = try FetchSourceOperation(sourceURL: sourceURL, context: context)
        Task {
            do {
                let source = try await fetchSourceOperation.execute()
                completionHandler(.success(source))
            } catch {
                completionHandler(.failure(error))
            }
        }
        return fetchSourceOperation
    }
    
    func fetchSources(completionHandler: @escaping (Result<(Set<Source>, NSManagedObjectContext), FetchSourcesError>) -> Void)
    {
        Task {
            let managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            var sourceData = [(objectID: NSManagedObjectID, sourceURL: URL)]()
            
            managedObjectContext.performAndWait {
                let sources = Source.all(in: managedObjectContext)
                sourceData = sources.map { ($0.objectID, $0.sourceURL) }
            }
            
            guard !sourceData.isEmpty else {
                completionHandler(.failure(.init(OperationError.noSources)))
                return
            }
            
            var fetchedSources = Set<Source>()
            var errors = [Source: Error]()
            
            await withTaskGroup(of: (NSManagedObjectID, Result<Void, Error>).self) { taskGroup in
                for data in sourceData {
                    taskGroup.addTask {
                        do {
                            let taskContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                            do {
                                let source = taskContext.performAndWait { taskContext.object(with: data.objectID) as! Source }
                                let context = StandaloneOperationContext(steps: [], dbBackgroundContext: taskContext)
                                let fetchSourceOperation = try FetchSourceOperation(source: source, context: context)
                                try await fetchSourceOperation.execute()
                                try taskContext.performAndWait {
                                    try taskContext.save()
                                }
                            } catch {
                                throw error
                            }
                            return (data.objectID, .success(()))
                        } catch {
                            return (data.objectID, .failure(error))
                        }
                    }
                }
                
                for await (objectID, result) in taskGroup {
                    managedObjectContext.performAndWait {
                        let source = managedObjectContext.object(with: objectID) as! Source
                        switch result {
                            case .success:
                                fetchedSources.insert(source)
                            case .failure(let nsError as NSError):
                                let title = String(format: NSLocalizedString("Unable to Refresh “%@” Source", comment: ""), source.name)
                                let error = nsError.withLocalizedTitle(title)
                                errors[source] = error
                                source.error = error.sanitizedForSerialization()
                        }
                    }
                }
            }
            
            await managedObjectContext.perform {
                if !errors.isEmpty {
                    let sourcesSet = Set(sourceData.compactMap { managedObjectContext.object(with: $0.objectID) as? Source })
                    completionHandler(.failure(.init(sources: sourcesSet, errors: errors, context: managedObjectContext)))
                } else {
                    completionHandler(.success((fetchedSources, managedObjectContext)))
                }
                NotificationCenter.default.post(name: AppManager.didFetchSourceNotification, object: self)
            }
        }
    }
    
    func syncAppIDs(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        Task {
            do {
                let managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                let context = AuthenticatedOperationContext(dbBackgroundContext: managedObjectContext)
                let authOperation = try AuthenticationOperation(context: context, presentingViewController: nil)
                try await authOperation.execute()
                
                let syncAppIDsOperation = try SyncAppIDsOperation(context: context)
                try await syncAppIDsOperation.execute()
                completionHandler(.success(()))
            } catch {
                completionHandler(.failure(error))
            }
        }
    }
    
    @discardableResult
    func updateKnownSources(completionHandler: @escaping (Result<([KnownSource], [KnownSource]), Error>) -> Void) -> UpdateKnownSourcesOperation
    {
        let updateKnownSourcesOperation = UpdateKnownSourcesOperation()
        Task {
            do {
                let result = try await updateKnownSourcesOperation.execute()
                completionHandler(.success(result))
            } catch {
                completionHandler(.failure(error))
            }
        }
        return updateKnownSourcesOperation
    }
    
    func updateAllSources(completion: @escaping (Result<Void, Error>) -> Void)
    {
        self.updateSourcesResult = nil
        
        self.fetchSources() { (result) in
            do
            {
                // Check if the result is failure and rethrow
                if case .failure(let error) = result {
                    throw error  // Rethrow the error
                }
                
                do
                {
                    let (_, context) = try result.get()
//                    debugLog("\n\n\n\(context.insertedObjects)\n\n\n")
//                    debugLog("\n\n\n\(context.updatedObjects)\n\n\n")
//                    debugLog("\n\n\n\(context.deletedObjects)\n\n\n")
                    try context.save()
                    
                    DispatchQueue.main.async {
                        self.updateSourcesResult = .success(())
                        completion(.success(()))
                    }
                }
                catch let error as AppManager.FetchSourcesError
                {
                    try error.managedObjectContext?.save()
                    throw error
                }
                catch let mergeError as MergeError
                {
                    guard let sourceID = mergeError.sourceID else { throw mergeError }
                    
                    let sanitizedError = (mergeError as NSError).sanitizedForSerialization()
                    DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                        do
                        {
                            guard let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), sourceID), in: context) else { return }
                            
                            source.error = sanitizedError
                            try context.save()
                        }
                        catch
                        {
                            debugLog("Failed to assign error \(sanitizedError.localizedErrorCode) to source \(sourceID). \(error.localizedDescription)")
                        }
                    }
                    
                    throw mergeError
                }
            }
            catch var error as NSError
            {
                if error.localizedTitle == nil
                {
                    error = error.withLocalizedTitle(NSLocalizedString("Unable to Refresh Store", comment: ""))
                }
                
                DispatchQueue.main.async {
                    self.updateSourcesResult = .failure(error)
                    completion(.failure(error))
                }
            }
        }
    }

    @discardableResult
    func install<T: AppProtocol>(_ app: T, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext(), completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> RefreshGroup
    {
        debugLog("[AppManager] install() called for app: \(app.bundleIdentifier)")
        let group = RefreshGroup(context: context)
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw context.error ?? OperationError.unknown() }
                completionHandler(result)
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        
        Task {
            do {
                try await self.perform([.install(app)], presentingViewController: presentingViewController, group: group)
            } catch {
                completionHandler(.failure(error))
            }
        }
        return group
    }

    func installIPA(at ipaURL: URL, context: AuthenticatedOperationContext = AuthenticatedOperationContext(), progressHandler: ((Progress) -> Void)? = nil) async throws -> InstalledApp
    {
        debugLog("[AppManager] installIPA() called for file: \(ipaURL.lastPathComponent)")
        guard ipaURL.pathExtension.lowercased() == "ipa" else { throw OperationError.invalidApp }

        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let unzippedAppDirectory = temporaryDirectory.appendingPathComponent("App")
        try FileManager.default.createDirectory(at: unzippedAppDirectory, withIntermediateDirectories: true)

        let unzippedApplicationURL = try FileManager.default.unzipAppBundle(at: ipaURL, toDirectory: unzippedAppDirectory)
        guard let application = ALTApplication(fileURL: unzippedApplicationURL) else { throw OperationError.invalidApp }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InstalledApp, Error>) in
            let group = self.install(application, presentingViewController: nil, context: context) { result in
                continuation.resume(with: result)
            }

            progressHandler?(group.progress)
        }
    }
    
    @discardableResult
    func update(_ installedApp: InstalledApp, to version: AppVersion? = nil, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext(), completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        debugLog("[AppManager] update() called for app: \(installedApp.bundleIdentifier)")
        guard let appVersion = version ?? installedApp.storeApp?.latestSupportedVersion else {
            completionHandler(.failure(OperationError.appNotFound(name: installedApp.name)))
            return Progress.discreteProgress(totalUnitCount: 1)
        }
        
        let group = RefreshGroup(context: context)
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw OperationError.unknown() }
                completionHandler(result)
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        assert(appVersion as AnyObject !== installedApp) // Make sure we never accidentally "update" to already installed app.
        
        Task{
            do {
                try await self.perform([.update(appVersion, customBundleIdentifier: installedApp.customBundleIdentifier)], presentingViewController: presentingViewController, group: group)
            } catch {
                completionHandler(.failure(error))
            }
        }
        
        return group.progress
    }
    
    @discardableResult
    func refresh(_ installedApps: [InstalledApp], presentingViewController: UIViewController?, group: RefreshGroup? = nil) -> RefreshGroup
    {
        debugLog("[AppManager] refresh() called for apps: \(installedApps.map { $0.bundleIdentifier })")
        let group = group ?? RefreshGroup()
        
        group.activeTask = Task {
            do {
                try await self.perform(installedApps.map { .refresh($0) }, presentingViewController: presentingViewController, group: group)
            } catch {
                group.context.error = error
                let results = Dictionary(uniqueKeysWithValues: installedApps.map { ($0.bundleIdentifier, Result<InstalledApp, Error>.failure(error)) })
                group.completionHandler?(results)
            }
        }
        
        return group
    }
    func activate(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] activate() called for app: \(installedApp.bundleIdentifier)")
        self.performSingleOperation(.activate(installedApp), presentingViewController: presentingViewController, completionHandler: completionHandler)
    }
    
    func deactivate(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] deactivate() called for app: \(installedApp.bundleIdentifier)")
        self.performSingleOperation(.deactivate(installedApp), presentingViewController: presentingViewController, completionHandler: completionHandler)
    }
    
    func deleteApp(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] deleteApp() called for app: \(installedApp.bundleIdentifier)")
        self.performSingleOperation(.deleteApp(installedApp), presentingViewController: presentingViewController, completionHandler: completionHandler)
    }
    
    @discardableResult
    func resign(_ installedApp: InstalledApp, alternateIconMode: AlternateIconMode = .preserve, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> RefreshGroup
    {
        debugLog("[AppManager] resign() called for app: \(installedApp.bundleIdentifier)")
        return self.performSingleOperation(.resign(installedApp, alternateIconMode: alternateIconMode), presentingViewController: presentingViewController, completionHandler: completionHandler)
    }
    
    func backup(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] backup() called for app: \(installedApp.bundleIdentifier)")
        self.performSingleOperation(.backup(installedApp), presentingViewController: presentingViewController, completionHandler: completionHandler)
    }
    
    func restore(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] restore() called for app: \(installedApp.bundleIdentifier)")
        self.performSingleOperation(.restore(installedApp), presentingViewController: presentingViewController, completionHandler: completionHandler)
    }
    
    func remove(_ installedApp: InstalledApp, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        debugLog("[AppManager] remove() called for app: \(installedApp.bundleIdentifier)")
        self.performVoidOperation(.remove(installedApp), presentingViewController: nil, completionHandler: completionHandler)
    }
    
    func enableJIT(for installedApp: InstalledApp, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        debugLog("[AppManager] enableJIT() called for app: \(installedApp.bundleIdentifier)")
        self.performVoidOperation(.enableJIT(installedApp), presentingViewController: nil, completionHandler: completionHandler)
    }

    @discardableResult
    func backgroundRefresh(_ installedApps: [InstalledApp],
                           presentsNotifications: Bool = false,
                           completionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], Error>) -> Void) throws -> BackgroundRefreshAppsOperation
    {
        let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let context = StandaloneOperationContext(steps: .backgroundRefreshApps, dbBackgroundContext: dbBackgroundContext)
        let backgroundRefreshAppsOperation = try BackgroundRefreshAppsOperation(installedApps: installedApps, context: context)
        Task.detached {
            do {
                backgroundRefreshAppsOperation.presentsFinishedNotification = presentsNotifications
                
                let result = try await backgroundRefreshAppsOperation.execute()
                completionHandler(.success(result))
            } catch {
                completionHandler(.failure(error))
            }
        }
        return backgroundRefreshAppsOperation
    }


    
    func installationProgress(for app: AppProtocol) -> Progress?
    {
        return self.progressLock.withLock {
            self.installationProgress[app.bundleIdentifier]
        }
    }
    
    func refreshProgress(for app: AppProtocol) -> Progress?
    {
        return self.progressLock.withLock {
            let bundleID = app.bundleIdentifier
            
            guard let progress = self.refreshProgress[bundleID] ?? self.installationProgress[bundleID] else {
                return nil
            }
            
            guard !progress.isCancelled else {
                self.refreshProgress[bundleID] = nil
                self.installationProgress[bundleID] = nil
                return nil
            }
            
            return progress
        }
    }
    
    func isActivelyManagingApp(withBundleID bundleID: String) -> Bool
    {
        let isActivelyManaging = self.installationProgress.keys.contains(bundleID) || self.refreshProgress.keys.contains(bundleID)
        return isActivelyManaging
    }
    
    var isActivelyManagingAnyApp: Bool
    {
        return self.progressLock.withLock {
            !self.installationProgress.isEmpty || !self.refreshProgress.isEmpty
        }
    }


    
    @discardableResult
    private func performSingleOperation(
        _ operation: AppOperation,
        presentingViewController: UIViewController?,
        context: AuthenticatedOperationContext = AuthenticatedOperationContext(),
        completionHandler: @escaping (Result<InstalledApp, Error>) -> Void
    ) -> RefreshGroup
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
        group.activeTask = Task {
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
    
    private func performVoidOperation(
        _ operation: AppOperation,
        presentingViewController: UIViewController?,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    )
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
    

}

private extension AppManager
{
    
    
    @discardableResult
    private func perform(_ operations: [AppOperation], presentingViewController: UIViewController?, group: RefreshGroup) async throws -> RefreshGroup
    {
        let operations = operations.filter { self.progress(for: $0) == nil || self.progress(for: $0)?.isCancelled == true }
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
                self.set(nil, for: operation)
            }
            if let error = group.context.error {            // Mark error as-is
                for operation in operations {
                    group.set(.failure(error), forAppWithBundleIdentifier: operation.bundleIdentifier)
                }
            }

            
            // Re-enable idleTimeout if no more actions are running and end background task
            Task { @MainActor in
                if UIApplication.shared.isIdleTimerDisabled && !self.isActivelyManagingAnyApp {
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
            
            for operation in operations
            {
                let progress = Progress.discreteProgress(totalUnitCount: 100)
                self.set(progress, for: operation)
                group.progress.addChild(progress, withPendingUnitCount: 100 / Int64(operations.count))
            }
            
            // take whatever it is - valid or nil, both works
            group.context.presentingViewController = presentingViewController
            
            /* Authenticate (if necessary) */
            if group.context.session == nil
            {
                do {
                    let authenticationOperation = try AuthenticationOperation(
                        context: group.context,
                        presentingViewController: presentingViewController,
                        skipDeviceRegistration: false
                    )
                    
                    let (team, cert, session) = try await authenticationOperation.execute()
                    group.context.team = team
                    group.context.certificate = cert
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
    
    private func performOperation(for operation: AppOperation, group: RefreshGroup) async throws {
        debugLog("[AppManager] performOperation: Starting execution for app: \(operation.bundleIdentifier)")
        let isSideStore = (operation.app as? ALTApplication)?.isAltStoreApp == true             ||
                           operation.bundleIdentifier.contains(ALTApplication.altstoreBundleID) ||
                           operation.bundleIdentifier == StoreApp.altstoreAppID
        
        if isSideStore && group.context.isSideStoreResignDismissed
        {
            debugLog("[AppManager] performOperation: SideStore resign dismissed, cancelling app: \(operation.bundleIdentifier)")
            group.set(.failure(OperationError.cancelled), forAppWithBundleIdentifier: operation.bundleIdentifier)
            return
        }
        
        do {
            let result = try await self.performPipeline(for: operation, group: group)
            // persist the result
            if let context = result.managedObjectContext {
                do {
                    try context.performAndWait {
                        if context.hasChanges {
                            try context.save()
                        }
                    }
                } catch {
                    debugLog("[AppManager] perform(): Failed to save InstalledApp to database. \(error.localizedDescription)")
                }
            }
            
            // request update view context's in-mem coredata caches (coz we worked so far on bg context)
            DatabaseManager.shared.viewContext.performAndWait {
                DatabaseManager.shared.viewContext.processPendingChanges()
            }
            
            group.set(.success(result), forAppWithBundleIdentifier: result.bundleIdentifier)
            
            if result.bundleIdentifier == StoreApp.altstoreAppID {
                let context = StandaloneOperationContext(steps: .scheduleExpirationWarningNotification, dbBackgroundContext: group.context.dbBackgroundContext)
                let scheduleNotifOp = try ScheduleExpirationWarningNotificationOperation(
                    installedApp: result,
                    context: context
                )
                try await scheduleNotifOp.execute()
            }
            
            WidgetCenter.shared.reloadAllTimelines()
            debugLog("[AppManager] performOperation: Completed execution successfully for app: \(operation.bundleIdentifier)")
            
        } catch {
            if Task.isCancelled {
                debugLog("[AppManager] performOperation: Execution CANCELLED for app: \(operation.bundleIdentifier)")
            } else {
                debugLog("[AppManager] performOperation: Execution failed for app: \(operation.bundleIdentifier) with error: \(error.localizedDescription)")
            }
            
            var appName: String!
            if let app = operation.app as? (NSManagedObject & AppProtocol) {
                if let context = app.managedObjectContext {
                    context.performAndWait {
                        appName = app.name
                    }
                } else {
                    appName = NSLocalizedString("Unknown App", comment: "")
                }
            } else {
                appName = operation.app.name
            }

            let localizedTitle: String
            switch operation
            {
                case .install:    localizedTitle = String(format: NSLocalizedString("Failed to Install %@",        comment: ""), appName)
                case .refresh:    localizedTitle = String(format: NSLocalizedString("Failed to Refresh %@",        comment: ""), appName)
                case .update:     localizedTitle = String(format: NSLocalizedString("Failed to Update %@",         comment: ""), appName)
                case .activate:   localizedTitle = String(format: NSLocalizedString("Failed to Activate %@",       comment: ""), appName)
                case .deactivate: localizedTitle = String(format: NSLocalizedString("Failed to Deactivate %@",     comment: ""), appName)
                case .deleteApp:  localizedTitle = String(format: NSLocalizedString("Failed to Deactivate %@",     comment: ""), appName)
                case .backup:     localizedTitle = String(format: NSLocalizedString("Failed to Backup %@",         comment: ""), appName)
                case .restore:    localizedTitle = String(format: NSLocalizedString("Failed to Restore %@ Backup", comment: ""), appName)
                case .resign:     localizedTitle = String(format: NSLocalizedString("Failed to Resign %@",         comment: ""), appName)
                case .remove:     localizedTitle = String(format: NSLocalizedString("Failed to Remove %@",         comment: ""), appName)
                case .enableJIT:  localizedTitle = String(format: NSLocalizedString("Failed to Enable JIT for %@", comment: ""), appName)
            }
            
            let nsError = error as NSError
            let mappedError = nsError.withLocalizedTitle(localizedTitle)
            group.set(.failure(mappedError), forAppWithBundleIdentifier: operation.bundleIdentifier)
            log(mappedError, operation: operation.loggedErrorOperation, app: operation.app)
        }
    }
    
    private func performPipeline(for operation: AppOperation, group: RefreshGroup) async throws -> InstalledApp
    {
        let pipelineSteps = PipelineDefinition.steps(for: operation)
        let context = InstallAppOperationContext(
            pipelineSteps: pipelineSteps,
            bundleIdentifier: operation.bundleIdentifier,
            authenticatedContext: group.context
        )
        
        if case .install(_, let customID) = operation { context.customBundleIdentifier  = customID }
        if case .update(_,  let customID) = operation { context.customBundleIdentifier  = customID }
        if case .resign(_,  let mode)     = operation { context.alternateIconMode       = mode }
        
        if let app = operation.app as? InstalledApp {
            context.app = ALTApplication(fileURL: app.fileURL)
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
        
        let additionalEntitlements = OperationEntitlements.defaultAdditionalEntitlements
        var finalApp: InstalledApp?
        
        let operationProgress = self.progress(for: operation)
        for pipelineStep in pipelineSteps {
            if let result = try await executeStep(
                pipelineStep.step,
                context: context,
                appOperation: operation,
                group: group,
                downloadingApp: downloadingApp,
                additionalEntitlements: additionalEntitlements,
                permissionsMode: permissionsMode,
                progress: operationProgress
            ) {
                finalApp = result
            }
        }
        
        guard let resultApp = finalApp ?? context.installedApp ?? (operation.app as? InstalledApp) else {
            throw OperationError.appNotFound(name: operation.app.name)
        }
        return resultApp
    }
    
    private func executeStep(_ step: PipelineStep,
                             context: InstallAppOperationContext,
                             appOperation: AppOperation,
                             group: RefreshGroup,
                             downloadingApp: AppProtocol,
                             additionalEntitlements: [ALTEntitlement: Any]?,
                             permissionsMode: VerifyAppOperation.PermissionReviewMode,
                             progress: Progress?) async throws -> InstalledApp?
    {
        var result: Any? = "()"
        var loggerType: any OperationLogging.Type
        
        defer {
            logOperationResult(result: result, loggerType: loggerType, operation: step)
        }

        do {
            switch step {
            case .preflightChecks:
                loggerType = PreflightChecksOperation.self
                let presentingViewController = group.context.presentingViewController
                let step = try PreflightChecksOperation(operations: [appOperation],
                                                        presentingViewController: presentingViewController,
                                                        context: group.context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .userCustomization:
                loggerType = UserCustomizationOperation.self
                let step = try UserCustomizationOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .downloadApp:
                loggerType = DownloadAppOperation.self
                let downloadedAppURL = context.temporaryDirectory.appendingPathComponent("App.app")
                let step = try DownloadAppOperation(app: downloadingApp,
                                                    destinationURL: downloadedAppURL,
                                                    context: context)
                let downloadedApp = try await step.execute(parentProgress: progress)
                context.app = downloadedApp
                result = downloadedApp
                return nil
                
            case .verifyApp:
                loggerType = VerifyAppOperation.self
                let step = try VerifyAppOperation(permissionsMode: permissionsMode, context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .cacheApp:
                loggerType = CacheAppOperation.self
                let step = try CacheAppOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .stageApp:
                loggerType = StageAppOperation.self
                let step = try StageAppOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .removeAppExtensions:
                loggerType = RemoveAppExtensionsOperation.self
                let localAppExtensions = (appOperation.app as? ALTApplication)?.appExtensions
                let step = try RemoveAppExtensionsOperation(context: context, localAppExtensions: localAppExtensions)
                result = try await step.execute(parentProgress: progress)
                return nil

                
            case .fetchProvisioningProfilesInstall:
                loggerType = FetchProvisioningProfilesInstallOperation.self
                let step = try FetchProvisioningProfilesInstallOperation(context: context)
                step.additionalEntitlements = additionalEntitlements
                let profiles = try await step.execute(parentProgress: progress)
                context.provisioningProfiles = profiles
                result = profiles
                return nil
                
            case .fetchProvisioningProfilesRefresh:
                loggerType = FetchProvisioningProfilesRefreshOperation.self
                let step = try FetchProvisioningProfilesRefreshOperation(context: context)
                let profiles = try await step.execute(parentProgress: progress)
                context.provisioningProfiles = profiles
                result = profiles
                return nil
                
            case .prepareAppExtensionBundleIDs:
                loggerType = PrepareAppExtensionBundleIDsOperation.self
                let step = try PrepareAppExtensionBundleIDsOperation(context: context)
                try await step.execute(parentProgress: progress)
                return nil
                
            case .changeAppIcon:
                loggerType = ChangeAppIconOperation.self
                let step = try ChangeAppIconOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .resignApp:
                loggerType = ResignAppOperation.self
                let step = try ResignAppOperation(context: context)
                let resignedApp = try await step.execute(parentProgress: progress)
                context.resignedApp = resignedApp
                result = resignedApp
                return nil
                
            case .exportResignedApp:
                loggerType = ExportResignedAppOperation.self
                let step = try ExportResignedAppOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .sendApp:
                loggerType = SendAppOperation.self
                let step = try SendAppOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .installApp:
                loggerType = InstallAppOperation.self
                let step = try InstallAppOperation(context: context, app: appOperation.app)
                let installedApp = try await step.execute(parentProgress: progress)
                context.installedApp = installedApp
                result = installedApp
                if let index = UserDefaults.standard.legacySideloadedApps?.firstIndex(of: installedApp.bundleIdentifier) {
                    UserDefaults.standard.legacySideloadedApps?.remove(at: index)
                }
                return installedApp
                
            case .stageBackupApp:
                loggerType = StageBackupAppOperation.self
                let installedApp = appOperation.app as? InstalledApp
                let step = try StageBackupAppOperation(app: installedApp, context: context)
                let resultApp = try await step.execute(parentProgress: progress)
                context.installedApp = resultApp
                result = resultApp
                return resultApp
                
            case .refreshApp:
                loggerType = RefreshAppOperation.self
                let step = try RefreshAppOperation(context: context)
                let installedApp = try await step.execute(parentProgress: progress)
                result = installedApp
                return nil
                
            case .backupAppData:
                loggerType = PerformBackupRestoreOperation.self
                let step = try PerformBackupRestoreOperation(action: .backup, context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .restoreAppData:
                loggerType = PerformBackupRestoreOperation.self
                let step = try PerformBackupRestoreOperation(action: .restore, context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .removeBackupData:
                loggerType = RemoveBackupDataOperation.self
                let step = try RemoveBackupDataOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .removeApp:
                loggerType = RemoveAppOperation.self
                let step = try RemoveAppOperation(context: context)
                let installedApp = try await step.execute(parentProgress: progress)
                result = installedApp
                return nil
                
            case .deactivateApp:
                loggerType = DeactivateAppOperation.self
                let app = appOperation.app as? InstalledApp
                let step = try DeactivateAppOperation(app: app, context: context)
                let installedApp = try await step.execute(parentProgress: progress)
                result = installedApp
                return nil
                
            case .enableJIT:
                loggerType = EnableJITOperation.self
                let step = try EnableJITOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
                
            case .cleanStagedApp:
                loggerType = CleanStagedAppOperation.self
                let step = try CleanStagedAppOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil
            }
        } catch {
            result = error
        }
        
        return nil
    }
    
    private func logOperationResult(result: Any?, loggerType: any OperationLogging.Type, operation: any OperationStep){
        if UserDefaults.standard.isVerboseOperationsLoggingEnabled &&
           OperationsLoggingControl.isLoggingEnabled(for: loggerType.self)
        {
            let resultStatus = (result is Error) ? "FAILURE" : "SUCCESS"
            debugLog(
            """
            [AppManager] ====> OPERATION: .\(operation) completed with: \(resultStatus) <====
                • Component: '\(loggerType)'
                • Result: \(result ?? "nil")
            """
            )
        }
    }

    
    func progress(for operation: AppOperation) -> Progress?
    {
        // Access outside critical section to avoid deadlock due to `bundleIdentifier` potentially calling performAndWait() on main thread.
        let bundleID = operation.bundleIdentifier
        
        return self.progressLock.withLock {
            switch operation
            {
            case .install, .update: 
                return self.installationProgress[bundleID]
            case .refresh, .activate, .deactivate, .deleteApp, .backup, .restore, .resign, .remove, .enableJIT: 
                return self.refreshProgress[bundleID]
            }
        }
    }
    
    private func set(_ progress: Progress?, for operation: AppOperation)
    {
        // Access outside critical section to avoid deadlock due to `bundleIdentifier` potentially calling performAndWait() on main thread.
        let bundleID = operation.bundleIdentifier
        
        self.progressLock.withLock {
            switch operation
            {
            case .install, .update: 
                self.installationProgress[bundleID] = progress
            case .refresh, .activate, .deactivate, .deleteApp, .backup, .restore, .resign, .remove, .enableJIT: 
                self.refreshProgress[bundleID] = progress
            }
            let operationName = String(describing: operation).components(separatedBy: "(").first ?? ""
            debugLog("[AppManager] setProgress: \(progress.map { "\($0)" } ?? "nil") for operation: .\(operationName), totalUnitCount: \(progress?.totalUnitCount ?? 0)")
        }
    }
}


