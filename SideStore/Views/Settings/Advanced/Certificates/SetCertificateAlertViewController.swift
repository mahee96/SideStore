//
//  SetCertificateAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class SetCertificateAlertViewController: UIViewController {
    let installedApp: InstalledApp
    let newCertificate: ALTCertificate
    
    init(installedApp: InstalledApp, certificate: ALTCertificate) {
        self.installedApp = installedApp
        self.newCertificate = certificate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let appCertSerial = installedApp.certificateSerialNumber
        var currentCertObj = CertificateManager.shared.getSigningCertificate(at: installedApp.fileURL)
        
        if currentCertObj == nil, let serial = appCertSerial {
            currentCertObj = CertificateManager.shared.getLocalCertificate(serialNumber: serial)
        }
        
        let currentName = currentCertObj?.name ?? "N/A"
        let currentMachine = currentCertObj?.machineName ?? "N/A"
        let currentSerial = currentCertObj?.serialNumber ?? appCertSerial ?? "None"
        let currentEmail = currentCertObj?.requesterEmail ?? "N/A"
        let currentBrief = getBriefInfo(for: currentCertObj?.data)
        let currentType = currentBrief?.type ?? "N/A"
        let currentValidity = currentBrief != nil ? "\(currentBrief!.validFrom) - \(currentBrief!.validUntil)" : "N/A"
        
        let targetName = newCertificate.name ?? "N/A"
        let targetMachine = newCertificate.machineName ?? "N/A"
        let targetSerial = newCertificate.serialNumber
        let targetEmail = newCertificate.requesterEmail ?? "N/A"
        let targetBrief = getBriefInfo(for: newCertificate.data)
        let targetType = targetBrief?.type ?? "N/A"
        let targetValidity = targetBrief != nil ? "\(targetBrief!.validFrom) - \(targetBrief!.validUntil)" : "N/A"
        
        debugLog("[SetCertAlert] appName: '\(installedApp.name)', appCertSerial: '\(appCertSerial ?? "nil")'")
        debugLog("[SetCertAlert] currentCertObj found: \(currentCertObj != nil), serial: '\(currentSerial)', name: '\(currentName)', machine: '\(currentMachine)', email: '\(currentEmail)'")
        debugLog("[SetCertAlert] targetCert serial: '\(targetSerial)', name: '\(targetName)', machine: '\(targetMachine)', email: '\(targetEmail)'")
        
        let details = """
          • App: \(installedApp.name)
          • Bundle ID: \(installedApp.resignedBundleIdentifier)

        [CURRENT APP CERTIFICATE]
          • Name: \(currentName)
          • Machine: \(currentMachine)
          • Serial: \(currentSerial)
          • Type: \(currentType)
          • Validity: \(currentValidity)
          • Email: \(currentEmail)

        [TARGET CERTIFICATE]
          • Name: \(targetName)
          • Machine: \(targetMachine)
          • Serial: \(targetSerial)
          • Type: \(targetType)
          • Validity: \(targetValidity)
          • Email: \(targetEmail)
        """
        
        let detailsLabel = UILabel()
        detailsLabel.text = details
        detailsLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailsLabel.textColor = .secondaryLabel
        detailsLabel.numberOfLines = 0
        detailsLabel.textAlignment = .left
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(detailsLabel)
        
        NSLayoutConstraint.activate([
            detailsLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            detailsLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            detailsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            detailsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
        ])
        
        self.preferredContentSize = CGSize(width: 290, height: 290)
    }
}
