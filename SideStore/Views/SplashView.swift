//
//  SplashView.swift
//  SideStore
//
//  Created by Magesh K on 14/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

final class SplashView: UIView {
    let iconView = UIImageView()
    let titleLabel = UILabel()

    init(frame: CGRect, appName: String) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        setupIcon()
        setupTitle(appName: appName)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupIcon() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.25
        container.layer.shadowOffset = CGSize(width: 0, height: 4)
        container.layer.shadowRadius = 8
        addSubview(container)

        iconView.image = UIImage(named: "AppIcon") ?? UIImage(named: "AppIcon60x60") ?? UIImage(systemName: "app.fill")
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = 24
        iconView.clipsToBounds = true
        container.addSubview(iconView)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            container.widthAnchor.constraint(equalToConstant: 120),
            container.heightAnchor.constraint(equalToConstant: 120),
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    private func setupTitle(appName: String) {
        titleLabel.text = appName
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }
}
