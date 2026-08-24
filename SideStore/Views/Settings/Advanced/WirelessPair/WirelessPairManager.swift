//
//  WirelessPairManager.swift
//  SideStore
//
//  Created by Magesh K on 04/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import Minimuxer

struct WirelessPairTarget: Identifiable, Hashable {
    var id: String { service.id }
    let service: DiscoveredService
    
    var name: String {
        if case .bonjour(let txt) = service.result.metadata,
           let customName = txt.dictionary["name"], !customName.isEmpty {
            return customName
        }
        return service.name
    }
    
    var rawType: String { service.type }
    
    var model: String? {
        if case .bonjour(let txt) = service.result.metadata {
            return txt.dictionary["model"]
        }
        return nil
    }
    
    var uuid: String? {
        if case .bonjour(let txt) = service.result.metadata {
            return txt.dictionary["uuid"] ?? txt.dictionary["deviceid"]
        }
        return nil
    }
    
    var typeBadge: String {
        if service.type.contains("manual-pairing") { return "Apple TV / Manual" }
        if service.type.contains("pairable-host") { return "Pairable Host" }
        if service.type.contains("remotepairing") { return "Remote Device" }
        return BonjourDiscoveryManager.friendlyName(for: service.type) ?? service.type
    }
    
    var iconName: String {
        if service.type.contains("manual-pairing") { return "appletv.fill" }
        if service.type.contains("pairable-host") { return "macbook.and.iphone" }
        return "antenna.radiowaves.left.and.right"
    }
}

@MainActor
final class WirelessPairManager: ObservableObject {
    static let shared = WirelessPairManager()
    
    @Published var statusText = "Ready to pair"
    @Published var subStatusText = "Tap Start to advertise this device on the local network."
    @Published var pinCode: String? = nil
    @Published var isAdvertising = false
    @Published var pairedDevice: MinimuxerPairedDevice? = nil
    @Published var errorMessage: String? = nil
    @Published var serviceID: String? = nil
    @Published var port: Int? = nil
    
    // Pairing Target Discovery State
    @Published var discoveredTargets: [WirelessPairTarget] = []
    @Published var selectedTarget: WirelessPairTarget? = nil
    @Published var resolvedService: ResolvedServiceInfo? = nil
    @Published var isScanning = false
    
    private let pairingServiceTypes = [
        "_remotepairing-manual-pairing._tcp",
        "_remotepairing._tcp",
        "_remotepairing-pairable-host._tcp"
    ]
    
    private let bonjour = BonjourDiscoveryManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    var fallbackConfigEndpoint: (ip: String, port: UInt16) {
        let config = ConnectionConfig.shared
        let port = remotePairingPortCache != 0 ? remotePairingPortCache : MinimuxerConstants.remotePairingPort

        guard config.useLocalVPN else {
            let remote = config.remoteServerIp.trimmingCharacters(in: .whitespacesAndNewlines)
            return (ip: !remote.isEmpty ? remote : AppConstants.Connection.defaultRemoteServerIP, port: port)
        }

        guard let ip = [config.overrideTunnelPeerIp, config.tunnelPeerIp]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return (ip: AppConstants.Connection.defaultOverrideIP, port: port)
        }

        return (ip: ip, port: port)
    }
    
    private init() {
        // Setup closures once
        wirelessPairing.onReadyToPair = { [weak self] (serviceID: String, port: Int) in
            Task { @MainActor in
                guard let self = self else { return }
                self.serviceID = serviceID
                self.port = port
                self.statusText = "Advertising server..."
                self.subStatusText = "Ensure both devices are on the same Wi-Fi."
            }
        }
        
        wirelessPairing.onPinReceived = { [weak self] (pin: String) in
            Task { @MainActor in
                guard let self = self else { return }
                self.pinCode = pin
                self.statusText = "Device Connected"
                self.subStatusText = "Enter the pairing code shown below on your other device settings screen."
            }
        }
        
        // Observe discovery results reactively
        bonjour.$instances
            .receive(on: DispatchQueue.main)
            .sink { [weak self] instances in
                self?.discoveredTargets = instances.map { WirelessPairTarget(service: $0) }
            }
            .store(in: &cancellables)
        
        // Observe resolver results reactively
        bonjour.$resolvedService
            .receive(on: DispatchQueue.main)
            .sink { [weak self] resolved in
                self?.resolvedService = resolved
            }
            .store(in: &cancellables)
    }
    
    func startDiscovery() {
        discoveredTargets.removeAll()
        selectedTarget = nil
        resolvedService = nil
        isScanning = true
        bonjour.discoverInstances(ofTypes: pairingServiceTypes, inDomain: "local.")
    }
    
    func stopDiscovery() {
        isScanning = false
        bonjour.stopAll()
    }
    
    func selectAndResolveTarget(_ target: WirelessPairTarget) {
        selectedTarget = target
        resolvedService = nil
        bonjour.resolveService(target.service)
    }
    
    func deselectTarget() {
        selectedTarget = nil
        resolvedService = nil
        bonjour.stopResolving()
    }
    
    func togglePairing() {
        if isAdvertising {
            stopPairing()
        } else {
            startPairing()
        }
    }
    
    func startPairing() {
        isAdvertising = true
        pinCode = nil
        errorMessage = nil
        serviceID = nil
        port = nil
        statusText = "Waiting for connection..."
        subStatusText = "Open Remote Pairing on your Apple TV / Vision Pro / host device to discover this server."
        
        let pairingFile = pairingFilePath()
        
        wirelessPairing.start(outPath: pairingFile) { [weak self] (result: Result<MinimuxerPairedDevice, Swift.Error>) in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.isAdvertising else { return }
                self.isAdvertising = false
                self.pinCode = nil
                self.serviceID = nil
                self.port = nil
                
                switch result {
                case .success(let device):
                    self.pairedDevice = device
                    self.statusText = "Success!"
                    self.subStatusText = "Successfully paired with \(device.name) (\(device.model))!\nPairing file saved to documents."
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.statusText = "Pairing Failed"
                    self.subStatusText = "An error occurred during pairing."
                }
            }
        }
    }

    func stopPairing() {
        wirelessPairing.stop()
        
        isAdvertising = false
        statusText = "Ready to pair"
        subStatusText = "Tap Start to advertise this device on the local network."
        pinCode = nil
        errorMessage = nil
        serviceID = nil
        port = nil
    }
    
    func triggerPairing(
        targetIp: String,
        targetPort: UInt16,
        completion: ((Result<MinimuxerPairedDevice, Swift.Error>) -> Void)? = nil
    ) {
        isAdvertising = true
        pinCode = nil
        errorMessage = nil
        serviceID = nil
        port = nil
        statusText = "Connecting to device..."
        subStatusText = "Initiating pairing handshake on \(targetIp):\(targetPort)..."
        
        let pairingFile = pairingFilePath()
        
        wirelessPairing.trigger(
            targetIp: targetIp,
            targetPort: targetPort,
            outPath: pairingFile
        ) { [weak self] (result: Result<MinimuxerPairedDevice, Swift.Error>) in
            Task { @MainActor in
                guard let self = self else { return }
                self.isAdvertising = false
                self.pinCode = nil
                self.serviceID = nil
                self.port = nil
                
                switch result {
                case .success(let device):
                    self.pairedDevice = device
                    self.statusText = "Success!"
                    self.subStatusText = "Successfully paired with \(device.name) (\(device.model))!\nPairing file saved to documents."
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.statusText = "Pairing Failed"
                    self.subStatusText = "An error occurred during pairing: \(error.localizedDescription)"
                }
                completion?(result)
            }
        }
    }
    
    private func pairingFilePath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("rp_pairing_file.plist").path
    }
}
