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

final class SignableCertificatesListViewController: UITableViewController {
    let installedApp: InstalledApp
    var onSelectCertificate: ((ALTCertificate) -> Void)?
    
    private var certificates: [ALTCertificate] = []
    
    init(installedApp: InstalledApp) {
        self.installedApp = installedApp
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Set Certificate", comment: "")
        self.certificates = CertificateManager.shared.loadAllSignableLocalCertificates()
        
        self.view.backgroundColor = .settingsBackground
        self.tableView.backgroundColor = .settingsBackground
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .settingsBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance
        
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        self.navigationItem.leftBarButtonItem?.tintColor = .white
        
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CertCell")
    }
    
    @objc private func cancelTapped() {
        self.dismiss(animated: true)
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
        
        let nav = UINavigationController(rootViewController: self)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presentingViewController.present(nav, animated: true)
    }
    
    // MARK: - UITableViewDataSource & Delegate
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return certificates.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CertCell", for: indexPath)
        let cert = certificates[indexPath.row]
        
        let certName = cert.name ?? "N/A"
        let machineName = cert.machineName ?? "N/A"
        let serialPrefix = String(cert.serialNumber.prefix(8))
        let isCurrent = (cert.serialNumber == installedApp.certificateSerialNumber)
        
        cell.textLabel?.text = "\(certName) [Machine: \(machineName)] (\(serialPrefix)...)" + (isCurrent ? " (Current)" : "")
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        cell.accessoryType = isCurrent ? .checkmark : .none
        cell.tintColor = .green
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let cert = certificates[indexPath.row]
        
        let contentVC = SetCertificateAlertViewController(installedApp: self.installedApp, certificate: cert)
        let confirmAlert = UIAlertController(
            title: NSLocalizedString("Set Certificate Confirmation", comment: ""),
            message: NSLocalizedString("Confirm applying this certificate:", comment: ""),
            preferredStyle: .alert
        )
        confirmAlert.setValue(contentVC, forKey: "contentViewController")
        
        let setAction = UIAlertAction(title: NSLocalizedString("Set & Resign", comment: ""), style: .default) { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.onSelectCertificate?(cert)
            }
        }
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        
        confirmAlert.addAction(cancelAction)
        confirmAlert.addAction(setAction)
        
        self.present(confirmAlert, animated: true)
    }
}
