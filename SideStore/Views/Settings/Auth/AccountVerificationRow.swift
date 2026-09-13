//
//  AccountVerificationRow.swift
//  SideStore
//
//  Created by Magesh K on 13/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign

final class AccountVerificationRow: InsetGroupTableViewCell {
    static let reuseIdentifier = "AccountVerificationRow"
    static let preferredHeight: CGFloat = 60.0
    
    enum Status: Equatable {
        case completed
        case checking
        case actionRequired(certMissing: Bool, deviceUnregistered: Bool)
    }
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let iconImageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    
    init(reuseIdentifier: String? = AccountVerificationRow.reuseIdentifier) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        self.setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupViews()
    }
    
    private func setupViews() {
        self.style = .bottom
        self.backgroundColor = nil
        self.contentView.backgroundColor = nil
        self.tintColor = UIColor.white.withAlphaComponent(0.6)
        self.layoutMargins = UIEdgeInsets(top: 8, left: 30, bottom: 8, right: 30)
        
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        self.subtitleLabel.numberOfLines = 2
        
        self.iconImageView.translatesAutoresizingMaskIntoConstraints = false
        self.iconImageView.contentMode = .scaleAspectFit
        self.iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        self.iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.spinner.color = .white
        self.spinner.hidesWhenStopped = true
        
        let textStack = UIStackView(arrangedSubviews: [self.titleLabel, self.subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        
        let mainStack = UIStackView(arrangedSubviews: [self.iconImageView, textStack, self.spinner])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center
        
        self.contentView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 30),
            mainStack.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -20),
            mainStack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 8),
            mainStack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -8),
            
            self.iconImageView.widthAnchor.constraint(equalToConstant: 24),
            self.iconImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with status: Status) {
        switch status {
        case .completed:
            self.titleLabel.text = nil
            self.subtitleLabel.text = nil
            self.iconImageView.image = nil
            self.iconImageView.isHidden = true
            self.spinner.stopAnimating()
            self.accessoryType = .none
            self.isSelectable = false
            
        case .checking:
            self.titleLabel.text = NSLocalizedString("Account Verification", comment: "")
            self.titleLabel.textColor = .white
            self.subtitleLabel.text = NSLocalizedString("Verifying account status...", comment: "")
            self.subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
            self.iconImageView.image = nil
            self.iconImageView.isHidden = true
            self.spinner.startAnimating()
            self.accessoryType = .none
            self.isSelectable = false
            
        case .actionRequired(let certMissing, let deviceUnregistered):
            self.titleLabel.text = NSLocalizedString("Action Required", comment: "")
            self.titleLabel.textColor = .systemOrange
            
            let subtitle: String
            if certMissing && deviceUnregistered {
                subtitle = NSLocalizedString("Signing certificate & device registration pending", comment: "")
            } else if certMissing {
                subtitle = NSLocalizedString("Active signing certificate pending", comment: "")
            } else {
                subtitle = NSLocalizedString("Device registration pending", comment: "")
            }
            self.subtitleLabel.text = subtitle
            self.subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
            
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            self.iconImageView.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: symbolConfig)?
                .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
            self.iconImageView.isHidden = false
            self.spinner.stopAnimating()
            self.accessoryType = .disclosureIndicator
            self.isSelectable = true
        }
    }
}

extension AccountVerificationRow {
    static func verifyStatus(for team: ALTTeam) async -> Status {
        let hasActiveCert = CertificateManager.shared.activeCertificate != nil || (try? CertificateManager.shared.loadActiveCertificate()) != nil
        let certMissing = !hasActiveCert
        let isDeviceRegistered = UserDefaults.standard.isDeviceRegistered
        
        if isDeviceRegistered {
            if certMissing {
                return .actionRequired(certMissing: true, deviceUnregistered: false)
            } else {
                return .completed
            }
        }
        
        do {
            let devices = try await DeveloperPortalProxy.shared.fetchDevices(for: team, types: .all)
            let udid = try await fetchUDID()
            let isMatch = devices.contains { $0.identifier.caseInsensitiveCompare(udid) == .orderedSame }
            
            if isMatch {
                UserDefaults.standard.isDeviceRegistered = true
                if certMissing {
                    return .actionRequired(certMissing: true, deviceUnregistered: false)
                } else {
                    return .completed
                }
            } else {
                return .actionRequired(certMissing: certMissing, deviceUnregistered: true)
            }
        } catch {
            verboseLog("[AccountVerificationRow] verifyStatus error fetching devices: \(error)")
            return .actionRequired(certMissing: certMissing, deviceUnregistered: true)
        }
    }
    
    static func resolvePendingActions(for status: Status, team: ALTTeam, presentingViewController: UIViewController) async {
        guard case .actionRequired(let certMissing, let deviceUnregistered) = status else { return }
        
        let handler = SignInFlowHandler(presentingViewController: presentingViewController)
        handler.showsDoItLater = true
        
        if deviceUnregistered {
            let deviceFlow = DeviceRegistrationFlow(handler: handler)
            do {
                _ = try await deviceFlow.registerCurrentDevice(for: team)
            } catch {
                verboseLog("[AccountVerificationRow] resolvePendingActions: device registration cancelled: \(error)")
                return
            }
        }
        
        if certMissing {
            let certFlow = CertificateProvisioningFlow(handler: handler)
            do {
                _ = try await certFlow.resolveCertificate(for: team)
            } catch {
                verboseLog("[AccountVerificationRow] resolvePendingActions: certificate provisioning cancelled: \(error)")
                return
            }
        }
    }
}
