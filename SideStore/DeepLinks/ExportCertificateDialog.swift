//
//  ExportCertificateDialog.swift
//  SideStore
//
//  Created by Magesh K on 8/2/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

@MainActor
public enum ExportCertificateDialog {
    
    public static func present(callbackTemplate: String, presentingViewController: UIViewController? = nil) {
        let rootVC = presentingViewController ?? UIApplication.shared.topViewController()
        guard let presentingVC = rootVC else { return }
        
        let alert = UIAlertController(
            title: localized("Export Certificate"),
            message: localized("Do you want to export your certificate to an external app? That app will be able to sign apps using your certificate."),
            preferredStyle: .alert
        )
        
        let exportAction = UIAlertAction(title: localized("Export"), style: .default) { _ in
            guard callbackTemplate.contains("$(BASE64_CERT)") else {
                let toast = ToastView(text: localized("No $(BASE64_CERT) placeholder found"), detailText: nil)
                toast.show(in: presentingVC)
                return
            }
            
            guard let encodedCert = CertificateManager.shared.activeSigningCertificateBase64Encoded,
                  let password = CertificateManager.shared.activeCertificate?.password else {
                let toast = ToastView(text: localized("Failed to find certificate or password"), detailText: nil)
                toast.show(in: presentingVC)
                return
            }
            
            var urlStr = callbackTemplate.replacingOccurrences(of: "$(BASE64_CERT)", with: encodedCert, options: .literal, range: nil)
            urlStr = urlStr.replacingOccurrences(of: "$(PASSWORD)", with: password, options: .literal, range: nil)
            
            guard let callbackURL = URL(string: urlStr) else {
                let toast = ToastView(text: localized("Failed to initialize callback URL!"), detailText: nil)
                toast.show(in: presentingVC)
                return
            }
            
            debugLog("[ExportCertificateDialog] Opening certificate callback URL: \(callbackURL.absoluteString)")
            UIApplication.shared.open(callbackURL)
        }
        
        alert.addAction(exportAction)
        alert.addAction(UIAlertAction(title: localized("Cancel"), style: .cancel))
        
        presentingVC.present(alert, animated: true)
    }
}
