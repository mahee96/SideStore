//
//  SignableCertificatesListViewController.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltStoreCore
@preconcurrency import AltSign

final class SignableCertificatesListViewController {
    let installedApp: InstalledApp
    var onSelectCertificate: ((ALTCertificate) -> Void)?
    
    init(installedApp: InstalledApp) {
        self.installedApp = installedApp
    }
    
    func present(from presentingViewController: UIViewController) {
        let signableCerts = CertificateManager.shared.loadAllSignableLocalCertificates()
        
        guard !signableCerts.isEmpty else {
            let alert = UIAlertController(
                title: NSLocalizedString("No Signing Certificates", comment: ""),
                message: NSLocalizedString("No valid signing certificates with private keys were found locally. Please import or create a certificate in Settings -> Certificates first.", comment: ""),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            presentingViewController.present(alert, animated: true)
            return
        }
        
        let alert = UIAlertController(
            title: NSLocalizedString("Set Certificate", comment: ""),
            message: String(format: NSLocalizedString("Choose a signing certificate for %@:", comment: ""), installedApp.name),
            preferredStyle: .actionSheet
        )
        
        for cert in signableCerts {
            let certName = cert.name ?? "N/A"
            let machineName = cert.machineName ?? "N/A"
            let serialPrefix = String(cert.serialNumber.prefix(8))
            let isCurrent = (cert.serialNumber == installedApp.certificateSerialNumber)
            let title = "\(certName) [Machine: \(machineName)] (\(serialPrefix)...)" + (isCurrent ? " (Current)" : "")
            
            let action = UIAlertAction(title: title, style: .default) { [weak presentingViewController, weak self] _ in
                guard let presentingVC = presentingViewController, let self = self else { return }
                
                let contentVC = SetCertificateAlertViewController(installedApp: self.installedApp, certificate: cert)
                let confirmAlert = UIAlertController(
                    title: NSLocalizedString("Set Certificate Confirmation", comment: ""),
                    message: NSLocalizedString("Confirm applying this certificate:", comment: ""),
                    preferredStyle: .alert
                )
                confirmAlert.setValue(contentVC, forKey: "contentViewController")
                
                let setAction = UIAlertAction(title: NSLocalizedString("Set & Resign", comment: ""), style: .default) { [weak self] _ in
                    self?.onSelectCertificate?(cert)
                }
                let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
                
                confirmAlert.addAction(cancelAction)
                confirmAlert.addAction(setAction)
                
                presentingVC.present(confirmAlert, animated: true)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = presentingViewController.view
            popover.sourceRect = CGRect(x: presentingViewController.view.bounds.midX, y: presentingViewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        presentingViewController.present(alert, animated: true)
    }
}
