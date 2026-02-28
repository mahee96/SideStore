//
//  MinimuxerWrapper.swift
//
//  Created by Magesh K on 22/02/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Minimuxer

var isMinimuxerReady: Bool {
    #if targetEnvironment(simulator)
    print("isMinimuxerReady = true on simulator")
    return true
    #else
    IfManager.shared.query()
    let dest = IfManager.shared.nextProbableSideVPN?.destIP
    var result = false
    if #available(iOS 26.4, *) {
        result = Minimuxer.ready(ifaddr: dest) && IfManager.shared.sideVPNPatched
    } else {
        result = Minimuxer.ready(ifaddr: dest)
    }
    print("isMinimuxerReady = \(result)")
    return result
    #endif
}

func minimuxerStartWithLogger(_ pairingFile: String, _ logPath: String, _ loggingEnabled: Bool) throws {
    defer { print("minimuxerStartWithLogger(pairingFile, logPath, dest, loggingEnabled) completed") }
    #if targetEnvironment(simulator)
    print("minimuxerStartWithLogger(pairingFile, logPath, loggingEnabled) is no-op on simulator")
    #else
    IfManager.shared.query()
    let dest = IfManager.shared.nextProbableSideVPN?.destIP
    print("minimuxerStartWithLogger(pairingFile, logPath, dest, loggingEnabled) invoked")
    try Minimuxer.startWithLogger(pairingFile: pairingFile, logPath: logPath, ifaddr: dest, isConsoleLoggingEnabled: loggingEnabled)
    #endif
}

func targetMinimuxerAddress() {
    defer { print("targetMinimuxerAddress() completed") }
    #if targetEnvironment(simulator)
    print("targetMinimuxerAddress() is no-op on simulator")
    #else
    print("targetMinimuxerAddress() invoked")
    Minimuxer.targetMinimuxerAddress()
    #endif
}

func installProvisioningProfiles(_ profileData: Data) throws {
    defer { print("installProvisioningProfiles(profileData) completed") }
    #if targetEnvironment(simulator)
    print("installProvisioningProfiles(profileData) is no-op on simulator")
    #else
    print("installProvisioningProfiles(profileData) invoked")
    try Minimuxer.installProvisioningProfile(profile: profileData)
    #endif
}

func removeProvisioningProfile(_ id: String) throws {
    defer { print("removeProvisioningProfile(id) completed") }
    #if targetEnvironment(simulator)
    print("removeProvisioningProfile(id) is no-op on simulator")
    #else
    print("removeProvisioningProfile(id) invoked")
    try Minimuxer.removeProvisioningProfile(id: id)
    #endif
}

func removeApp(_ bundleId: String) throws {
    defer { print("removeApp(bundleId) completed") }
    #if targetEnvironment(simulator)
    print("removeApp(bundleId) is no-op on simulator")
    #else
    print("removeApp(bundleId) invoked")
    try Minimuxer.removeApp(bundleId: bundleId)
    #endif
}

func yeetAppAFC(_ bundleId: String, _ rawBytes: Data) throws {
    defer { print("yeetAppAFC(bundleId, rawBytes) completed") }
    #if targetEnvironment(simulator)
    print("yeetAppAFC(bundleId, rawBytes) is no-op on simulator")
    #else
    print("yeetAppAFC(bundleId, rawBytes) invoked")
    try Minimuxer.yeetAppAfc(bundleId: bundleId, ipaBytes: rawBytes)
    #endif
}

func installIPA(_ bundleId: String) throws {
    defer { print("installIPA(bundleId) completed") }
    #if targetEnvironment(simulator)
    print("installIPA(bundleId) is no-op on simulator")
    #else
    print("installIPA(bundleId) invoked")
    try Minimuxer.installIpa(bundleId: bundleId)
    #endif
}

func fetchUDID() -> String? {
    defer { print("fetchUDID() completed") }
    #if targetEnvironment(simulator)
    print("fetchUDID() is no-op on simulator")
    return "XXXXX-XXXX-XXXXX-XXXX"
    #else
    print("fetchUDID() invoked")
    return Minimuxer.fetchUDID()
    #endif
}

func debugApp(_ appId: String) throws {
    defer { print("debugApp(appId) completed") }
    #if targetEnvironment(simulator)
    print("debugApp(appId) is no-op on simulator")
    #else
    print("debugApp(appId) invoked")
    try Minimuxer.debugApp(appId: appId)
    #endif
}

func attachDebugger(_ pid: UInt32) throws {
    defer { print("attachDebugger(pid) completed") }
    #if targetEnvironment(simulator)
    print("attachDebugger(pid) is no-op on simulator")
    #else
    print("attachDebugger(pid) invoked")
    try Minimuxer.attachDebugger(pid: pid)
    #endif
}

func startAutoMounter(_ docsPath: String) {
    defer { print("startAutoMounter(docsPath) completed") }
    #if targetEnvironment(simulator)
    print("startAutoMounter(docsPath) is no-op on simulator")
    #else
    print("startAutoMounter(docsPath) invoked")
    Minimuxer.startAutoMounter(docsPath: docsPath)
    #endif
}

func dumpProfiles(_ docsPath: String) throws -> String {
    defer { print("dumpProfiles(docsPath) completed") }
    #if targetEnvironment(simulator)
    print("dumpProfiles(docsPath) is no-op on simulator")
    return ""
    #else
    print("dumpProfiles(docsPath) invoked")
    return try Minimuxer.dumpProfiles(docsPath: docsPath)
    #endif
}

func setMinimuxerDebug(_ debug: Bool) {
    defer { print("setMinimuxerDebug(debug) completed") }
    print("setMinimuxerDebug(debug) invoked")
    Minimuxer.setDebug(debug)
}

extension MinimuxerError: @retroactive LocalizedError {
    public var failureReason: String? {
        switch self {
        case .NoDevice:
            return NSLocalizedString("Cannot fetch the device from the muxer", comment: "")
        case .NoConnection:
            return NSLocalizedString("Unable to connect to the device, make sure LocalDevVPN is enabled and you're connected to Wi-Fi. This could mean an invalid pairing.", comment: "")
        case .PairingFile:
            return NSLocalizedString("Invalid pairing file. Your pairing file either didn't have a UDID, or it wasn't a valid plist. Please use iloader to replace it.", comment: "")
        case .CreateDebug:
            return createService(name: "debug")
        case .LookupApps:
            return getFromDevice(name: "installed apps")
        case .FindApp:
            return getFromDevice(name: "path to the app")
        case .BundlePath:
            return getFromDevice(name: "bundle path")
        case .MaxPacket:
            return setArgument(name: "max packet")
        case .WorkingDirectory:
            return setArgument(name: "working directory")
        case .Argv:
            return setArgument(name: "argv")
        case .LaunchSuccess:
            return getFromDevice(name: "launch success")
        case .Detach:
            return NSLocalizedString("Unable to detach from the app's process", comment: "")
        case .Attach:
            return NSLocalizedString("Unable to attach to the app's process", comment: "")
        case .CreateInstproxy:
            return createService(name: "instproxy")
        case .CreateAfc:
            return createService(name: "AFC")
        case .RwAfc:
            return NSLocalizedString("AFC was unable to manage files on the device.", comment: "")
        case .InstallApp(let message):
            return NSLocalizedString("Unable to install the app: \(message)", comment: "")
        case .UninstallApp:
            return NSLocalizedString("Unable to uninstall the app", comment: "")
        case .CreateMisagent:
            return createService(name: "misagent")
        case .ProfileInstall:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .ProfileRemove:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .CreateLockdown:
            return NSLocalizedString("Unable to connect to lockdown", comment: "")
        case .CreateCoreDevice:
            return NSLocalizedString("Unable to connect to core device proxy", comment: "")
        case .CreateSoftwareTunnel:
            return NSLocalizedString("Unable to create software tunnel", comment: "")
        case .CreateRemoteServer:
            return NSLocalizedString("Unable to connect to remote server", comment: "")
        case .CreateProcessControl:
            return NSLocalizedString("Unable to connect to process control", comment: "")
        case .GetLockdownValue:
            return NSLocalizedString("Unable to get value from lockdown", comment: "")
        case .Connect:
            return NSLocalizedString("Unable to connect to TCP port", comment: "")
        case .Close:
            return NSLocalizedString("Unable to close TCP port", comment: "")
        case .XpcHandshake:
            return NSLocalizedString("Unable to get services from XPC", comment: "")
        case .NoService:
            return NSLocalizedString("Device did not contain service", comment: "")
        case .InvalidProductVersion:
            return NSLocalizedString("Service version was in an unexpected format", comment: "")
        case .CreateFolder:
            return NSLocalizedString("Unable to create DDI folder", comment: "")
        case .DownloadImage:
            return NSLocalizedString("Unable to download DDI", comment: "")
        case .ImageLookup:
            return NSLocalizedString("Unable to lookup DDI images", comment: "")
        case .ImageRead:
            return NSLocalizedString("Unable to read images to memory", comment: "")
        case .Mount:
            return NSLocalizedString("Mount failed", comment: "")
        }
    }

    fileprivate func createService(name: String) -> String {
        String(format: NSLocalizedString("Cannot start a %@ server on the device.", comment: ""), name)
    }

    fileprivate func getFromDevice(name: String) -> String {
        String(format: NSLocalizedString("Cannot fetch %@ from the device.", comment: ""), name)
    }

    fileprivate func setArgument(name: String) -> String {
        String(format: NSLocalizedString("Cannot set %@ on the device.", comment: ""), name)
    }
}
