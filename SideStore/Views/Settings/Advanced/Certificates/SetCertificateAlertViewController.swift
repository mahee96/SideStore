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
        
        var isCertificateBad = false
        let activeCertObj: ALTCertificate? = {
            do {
                return try CertificateManager.shared.getActiveCertificate()
            } catch {
                debugLog("[SetCertificateAlertViewController] Failed to load active certificate: \(error)")
                isCertificateBad = true
                return nil
            }
        }()
        
        let fallbackLabel = isCertificateBad ? "BAD" : "N/A"
        let activeName = activeCertObj?.name ?? fallbackLabel
        let activeMachine = activeCertObj?.machineName ?? fallbackLabel
        let activeSerial = activeCertObj?.serialNumber ?? fallbackLabel
        let activeEmail = activeCertObj?.requesterEmail ?? fallbackLabel
        
        let targetName = newCertificate.name ?? "N/A"
        let targetMachine = newCertificate.machineName ?? "N/A"
        let targetSerial = newCertificate.serialNumber
        let targetEmail = newCertificate.requesterEmail ?? "N/A"
        
        let details = """
          • App: \(installedApp.name)
          • Bundle ID: \(installedApp.resignedBundleIdentifier)

        [ACTIVE CERTIFICATE]
          • Name: \(activeName)
          • Machine: \(activeMachine)
          • Serial: \(activeSerial)
          • Email: \(activeEmail)

        [TARGET CERTIFICATE]
          • Name: \(targetName)
          • Machine: \(targetMachine)
          • Serial: \(targetSerial)
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
        
        self.preferredContentSize = CGSize(width: 290, height: 250)
    }
}
