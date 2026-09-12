//
//  InstallAppDialog.swift
//  SideStore
//
//  Created by Magesh K on 8/2/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

@MainActor
public enum InstallAppDialog {
    
    public static func present(
        ipaURL: URL,
        from presentingViewController: UIViewController? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let rootVC = presentingViewController ?? UIApplication.shared.topViewController()
        guard let presentingVC = rootVC else {
            onCancel()
            return
        }
        
        let appName = ipaURL.deletingPathExtension().lastPathComponent
        
        let alert = UIAlertController(
            title: localized("Install App"),
            message: localized("Would you like to install \"\(appName)\"?"),
            preferredStyle: .alert
        )
        
        let installAction = UIAlertAction(title: localized("Install"), style: .default) { _ in
            onConfirm()
        }
        
        let cancelAction = UIAlertAction(title: localized("Cancel"), style: .cancel) { _ in
            onCancel()
        }
        
        alert.addAction(installAction)
        alert.addAction(cancelAction)
        
        presentingVC.present(alert, animated: true)
    }
}
