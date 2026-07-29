//
//  InstallAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
import UIKit
import UserNotifications
import Foundation
import Network
@preconcurrency import AltStoreCore
import CoreData
@preconcurrency import AltSign

let shortcutURLonDelay = URL(string: "shortcuts://run-shortcut?name=TurnOnDataDelay")!

@objc(InstallAppOperation)
final class InstallAppOperation: ResultOperation<InstalledApp>, OperationLogging, @unchecked Sendable {
    private static let selfInstallSuspendDelayNs: UInt64 = 2_000_000_000

    let context: InstallAppOperationContext
    let storeApp: StoreApp?
    
    private var didCleanUp = false
    
    init(context: InstallAppOperationContext, app: any AppProtocol) {
        self.context = context
        self.storeApp = app as? StoreApp
        
        super.init()
        
        self.progress.totalUnitCount = 100
    }
    
    override func main() {
        super.main()
        
        if let error = context.error {
            self.finish(.failure(error))
            return
        }
        
        guard
            let certificate = context.certificate,
            let resignedApp = context.resignedApp,
            let provisioningProfiles = context.provisioningProfiles
        else {
            return self.finish(.failure(OperationError.invalidParameters(
                "InstallAppOperation.main: self.context.certificate or self.context.resignedApp or self.context.provisioningProfiles is nil"
            )))
        }

        #if !targetEnvironment(simulator)
        guard resignedApp.provisioningProfile != nil else {
            return finish(.failure(OperationError.invalidApp))
        }
        #endif

        @Managed var appVersion = context.appVersion
        let storeBuildVersion = $appVersion.buildVersion
        
        Task {
            do {
                let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                let installedApp = try await installApp(
                    in: backgroundContext,
                    certificate: certificate,
                    resignedApp: resignedApp,
                    provisioningProfiles: provisioningProfiles,
                    storeBuildVersion: storeBuildVersion
                )
                self.finish(.success(installedApp))
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    override func finish(_ result: Result<InstalledApp, Error>) {
        cleanUp()
        
        // Only remove refreshed IPA when finished.
        if let app = context.app {
            let updatedApp = AnyApp(from: app, bundleId: self.context.targetBundleIdentifier)
            let fileURL = InstalledApp.refreshedIPAURL(for: updatedApp)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    debugLog("[InstallAppOperation] Removed refreshed IPA")
                } catch {
                    debugLog("[InstallAppOperation] Failed to remove refreshed .ipa: \(error)")
                }
            }
        }
        
        super.finish(result)
    }
    
    private func installApp(in backgroundContext: NSManagedObjectContext,
                            certificate: ALTCertificate,
                            resignedApp: ALTApplication,
                            provisioningProfiles: [String: ALTProvisioningProfile],
                            storeBuildVersion: String?) async throws -> InstalledApp
    {
        let (installedApp, isDifferentSideStore, bundleID, isSelfReinstall) = try await backgroundContext.perform {
            /* App */
            let installedApp = try self.fetchOrCreateApp(
                in: backgroundContext,
                certificate: certificate,
                resignedApp: resignedApp,
                storeBuildVersion: storeBuildVersion
            )
            
            let isDifferentSideStore = Self.isDifferentSideStoreContainer(installedApp, resignedApp)
            if isDifferentSideStore {
                self.debugLog("""
                [WARN] Skipped inserting/updating into InstalledApp table for SideStore:
                    - Resigned Bundle ID: '\(resignedApp.bundleIdentifier)'
                    - Active Container Bundle ID: '\(installedApp.resignedBundleIdentifier)'
                    Reason: A different bundle ID installs SideStore as a new app container which initializes its own database upon launch.
                            Hence we do not perist current change to prevent corruption of current sidestore's database entry.
                    
                """)
            } else {
                /* App Extensions */
                let installedExtensions = try self.fetchOrCreateExtensions(
                    for: resignedApp,
                    installedApp: installedApp,
                    in: backgroundContext
                )
                installedApp.appExtensions = installedExtensions
                
                // Remove stale "PlugIns" (Extensions) from currently installed App
                self.removeStaleAppExtensions(for: installedApp)
                self.context.beginInstallationHandler?(installedApp)
                self.updateActiveAppsStatus(
                    for: installedApp,
                    provisioningProfiles: provisioningProfiles,
                    in: backgroundContext
                )
            }
            
            // TODO: @mahee96: this is commented out since we don't want to persist staging data yet before install is complete
            let isSelfReinstall = !isDifferentSideStore &&
                                   installedApp.storeApp?.bundleIdentifier.range(of: Bundle.Info.appbundleIdentifier) != nil
//            if isSelfReinstall {
//                // Flush changes to disk now in case the changes are lost when iOS kills current process
//                do {
//                    try installedApp.managedObjectContext?.save()
//                } catch {
//                    self.debugLog("Failed to flush installedApp to disk: \(error)")
//                }
//            }
            
            return (installedApp, isDifferentSideStore, installedApp.bundleIdentifier, isSelfReinstall)
        }
        
        // Temporary directory and resigned .ipa no longer needed — delete now before AltStore quits.
        cleanUp()
        
        // Self-reinstall background suspension
        if isSelfReinstall {
            self.handleSelfReinstallation(for: installedApp)
        }
        
        // Phase 2: IPA installation
        try await installIPA(bundleID)
        
        // Phase 3: Post-install CoreData write — update refreshedDate + save.
        if !isDifferentSideStore {
            try await backgroundContext.perform {
                installedApp.refreshedDate = Date()
                try installedApp.managedObjectContext?.save()
            }
        }
        return installedApp
    }
    
    private static func isDifferentSideStoreContainer(_ installedApp: InstalledApp, _ resignedApp: ALTApplication) -> Bool {
        return ((installedApp.bundleIdentifier == StoreApp.altstoreAppID) || resignedApp.isAltStoreApp) &&
                (resignedApp.bundleIdentifier != installedApp.resignedBundleIdentifier)
    }

    private func fetchOrCreateApp(in backgroundContext: NSManagedObjectContext,
                                  certificate: ALTCertificate,
                                  resignedApp: ALTApplication, storeBuildVersion: String?) throws -> InstalledApp
    {
        let installedApp = try InstalledApp.first(
                                satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), context.bundleIdentifier),
                                in: backgroundContext
                            ) ?? InstalledApp(
                                resignedApp: resignedApp,
                                originalBundleIdentifier: self.context.bundleIdentifier,
                                certificateSerialNumber: certificate.serialNumber,
                                storeBuildVersion: storeBuildVersion,
                                context: backgroundContext
                            )
        if !Self.isDifferentSideStoreContainer(installedApp, resignedApp) {
            installedApp.update(
                resignedApp: resignedApp,
                certificateSerialNumber: certificate.serialNumber,
                storeBuildVersion: storeBuildVersion
            )
            installedApp.customBundleIdentifier = context.customBundleIdentifier
            installedApp.useMainProfile = context.useMainProfile
            if let team = DatabaseManager.shared.activeTeam(in: backgroundContext) {
                installedApp.team = team
            }
            if let storeApp {
                installedApp.storeApp = backgroundContext.object(with: storeApp.objectID) as? StoreApp
            }
            // update alternate icon
            switch context.alternateIconMode {
                case .set(let alternateIconURL):
                    guard FileManager.default.fileExists(atPath: alternateIconURL.path) else { break }
                    installedApp.hasAlternateIcon = true
                    guard alternateIconURL != installedApp.alternateIconURL else { break }
                    do {
                        try FileManager.default.copyItem(
                            at: alternateIconURL,
                            to: installedApp.alternateIconURL,
                            shouldReplace: true
                        )
                        self.debugLog("[InstallAppOperation] Copied alternate icon at: \(alternateIconURL) to: \(installedApp.alternateIconURL)")
                    } catch {
                        self.debugLog("[InstallAppOperation] Failed to copy alternate icon: \(error)")
                    }
                case .remove:
                    try? FileManager.default.removeItem(at: installedApp.alternateIconURL)
                    installedApp.hasAlternateIcon = false
                case .preserve:
                    break
            }
        }

        return installedApp
    }

    private func fetchOrCreateExtensions(for resignedApp: ALTApplication,
                                         installedApp: InstalledApp,
                                         in backgroundContext: NSManagedObjectContext) throws -> Set<InstalledExtension>
    {
        var installedExtensions = Set<InstalledExtension>()
        
        if let bundle = Bundle(url: resignedApp.fileURL),
            let directory = bundle.builtInPlugInsURL,
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants])
        {
            for case let fileURL as URL in enumerator {
                guard let appExtensionBundle = Bundle(url: fileURL) else { continue }
                guard let appExtension = ALTApplication(fileURL: appExtensionBundle.bundleURL) else { continue }
                
                let parentBundleID = context.bundleIdentifier
                let resignedParentBundleID = resignedApp.bundleIdentifier
                
                let resignedBundleID = appExtension.bundleIdentifier
                let appExBundleID = resignedBundleID.replacingOccurrences(of: resignedParentBundleID, with: parentBundleID)
                
                self.debugLog("`InstalledAppOperation: parentBundleID`: \(parentBundleID)")
                self.debugLog("`InstalledAppOperation: resignedParentBundleID`: \(resignedParentBundleID)")
                self.debugLog("`InstalledAppOperation: appExBundleID`: \(appExBundleID)")
                self.debugLog("`InstalledAppOperation: resignedAppExBundleID`: \(resignedBundleID)")
                
                let installedExtension = try installedApp.appExtensions
                                                .first(where: { $0.bundleIdentifier == appExBundleID })
                                            ?? InstalledExtension(
                                                resignedAppExtension: appExtension,
                                                originalBundleIdentifier: appExBundleID,
                                                context: backgroundContext
                                            )
                installedExtension.update(resignedAppExtension: appExtension)
                installedExtensions.insert(installedExtension)
            }
        }

        return installedExtensions
    }

    private func removeStaleAppExtensions(for installedApp: InstalledApp) {
        if let installedAppExns = ALTApplication(fileURL: installedApp.fileURL)?.appExtensions {
            let currentAppExns = Set(installedApp.appExtensions).map{ $0.bundleIdentifier }
            let staleAppExns = installedAppExns.filter{ !currentAppExns.contains($0.bundleIdentifier) }
            
            for staleAppExn in staleAppExns {
                do {
                    try FileManager.default.removeItem(at: staleAppExn.fileURL)
                    self.debugLog("[InstallAppOperation] removed stale app-extension: \(staleAppExn.fileURL)")
                } catch {
                    self.debugLog("[InstallAppOperation] remove appExtensions Error: \(error)")
                }
            }
        }
    }

    private func updateActiveAppsStatus(for installedApp: InstalledApp,
                                        provisioningProfiles: [String: ALTProvisioningProfile],
                                        in backgroundContext: NSManagedObjectContext
    ){
        if let sideloadedAppsLimit = UserDefaults.standard.activeAppsLimit,
               provisioningProfiles.contains(where: { $1.isFreeProvisioningProfile == true })
        {
            // When installing these new profiles, AltServer will remove all non-active profiles to ensure we remain under limit.
            let fetchRequest = InstalledApp.activeAppsFetchRequest()
            fetchRequest.includesPendingChanges = false
            
            // Only free-cert-signed apps count against the free limit
            var activeApps = InstalledApp.fetch(fetchRequest, in: backgroundContext)
                                         .filter { ($0.team?.type ?? .unknown) == .free }
            
            if !activeApps.contains(installedApp) {
                let activeAppsCount = activeApps.map { $0.requiredActiveSlots }.reduce(0, +)
                
                let availableActiveApps = max(sideloadedAppsLimit - activeAppsCount, 0)
                if installedApp.requiredActiveSlots <= availableActiveApps {
                    // This app has not been explicitly activated, but there are enough slots available,
                    // so implicitly activate it.
                    installedApp.isActive = true
                    activeApps.append(installedApp)
                } else {
                    installedApp.isActive = false
                }
            }
        } else {
            installedApp.isActive = true
        }
    }
        
    private func suspendToHomeScreen() {
        // using GCD on main queue for determinism
        DispatchQueue.main.async {
            self.debugLog("[InstallAppOperation] Going home")
            if self.context.shouldTurnOffData {
                UIApplication.shared.open(shortcutURLonDelay, options: [:]) { _ in
                    self.debugLog("[InstallAppOperation] Cell OFF Shortcut finished execution.")
                }
            }
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }

    private func handleSelfReinstallation(for installedApp: InstalledApp) {
        // Reinstalling ourself will hang until we leave the app, so we need to exit it without force closing
        Task.detached {
            try? await Task.sleep(nanoseconds: Self.selfInstallSuspendDelayNs)

            let state = await MainActor.run { UIApplication.shared.applicationState }
            guard state == .active else {
                self.debugLog("[InstallAppOperation] We are not in the foreground, let's not do anything")
                return
            }
                
            let delaySeconds = Self.selfInstallSuspendDelayNs / 1_000_000_000
            self.debugLog("[InstallAppOperation] We are still installing after \(delaySeconds) seconds")
            
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .ephemeral, .provisional:
                    self.verboseLog("[InstallAppOperation] Notifications are enabled")

                    let content = UNMutableNotificationContent()
                    content.title = "Refreshing..."
                    content.body = "SideStore will automatically move to the homescreen to finish refreshing!"
                    let notification = UNNotificationRequest(identifier: Bundle.Info.appbundleIdentifier + ".FinishRefreshNotification", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
                    UNUserNotificationCenter.current().add(notification)
                    
                    self.suspendToHomeScreen()

                default:
                    self.verboseLog("[InstallAppOperation] Notifications are not enabled")

                    DispatchQueue.main.async {
                        let alert = UIAlertController(
                            title: "Finish Refresh",
                            message: """
                            To finish refreshing, SideStore must be moved to the background. To do this, you can either go to the Home Screen manually or by hitting Continue. Please reopen SideStore after doing this.
                            """,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default, handler: { _ in
                            self.suspendToHomeScreen()
                        }))

                        let presenter = self.context.authenticatedContext.presentingViewController 
                                        ?? UIApplication.shared.connectedScenes
                                            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                                            .first?.rootViewController

                        if var topVC = presenter {
                            while let presented = topVC.presentedViewController {
                                topVC = presented
                            }
                            topVC.present(alert, animated: true)
                        } else {
                            self.debugLog("[InstallAppOperation] No view controller available, suspending directly")
                            self.suspendToHomeScreen()
                        }
                    }
                }
            }
        }
    }
    
    private func cleanUp() {
        guard !didCleanUp else { return }
        didCleanUp = true
        
        do {
            try FileManager.default.removeItem(at: context.temporaryDirectory)
        } catch {
            debugLog("[InstallAppOperation] Failed to remove temporary directory. \(error)")
        }
    }
}
