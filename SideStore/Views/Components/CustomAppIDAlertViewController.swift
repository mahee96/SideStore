//
//  CustomAppIDAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 28/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation

class AppendTeamIDCheckboxView: UIView, UITextFieldDelegate {
    let checkboxButton = UIButton(type: .system)
    let label = UILabel()
    weak var textField: UITextField?
    var teamID: String = ""
    
    var suffix: String {
        teamID.isEmpty ? "" : ".\(teamID)"
    }
    
    var isChecked: Bool = true {
        didSet {
            updateButtonImage()
            updateTextFieldSuffix()
            onToggle?(isChecked)
        }
    }
    
    var onToggle: ((Bool) -> Void)?
    
    init(isChecked: Bool = true, teamID: String = "", textField: UITextField? = nil) {
        self.isChecked = isChecked
        self.teamID = teamID
        self.textField = textField
        super.init(frame: .zero)
        setup()
        if let tf = textField {
            attach(to: tf, teamID: teamID)
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    func attach(to textField: UITextField, teamID: String) {
        self.textField = textField
        self.teamID = teamID
        textField.delegate = self
        updateTextFieldSuffix()
    }

    private func updateTextFieldSuffix() {
        guard let tf = textField, !suffix.isEmpty else { return }
        let current = tf.text ?? ""
        if isChecked {
            if !current.hasSuffix(suffix) {
                tf.text = current + suffix
            }
        } else {
            if current.hasSuffix(suffix) {
                tf.text = String(current.dropLast(suffix.count))
            }
        }
    }
    
    func cleanBaseID() -> String {
        guard let text = textField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return "" }
        if isChecked && !suffix.isEmpty && text.hasSuffix(suffix) {
            return String(text.dropLast(suffix.count))
        }
        return text
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard isChecked && !suffix.isEmpty else { return true }
        guard let currentText = textField.text as NSString? else { return true }
        
        let suffixLength = (suffix as NSString).length
        let suffixStartIndex = currentText.length - suffixLength
        guard suffixStartIndex >= 0 else { return true }
        
        // Full replacement (e.g. Select All + paste/type)
        if range.location == 0 && range.length == currentText.length {
            let clean = string.hasSuffix(suffix) ? string : (string + suffix)
            textField.text = clean
            return false
        }
        
        // Block any deletion or edit that touches or encroaches on the persistent suffix
        if range.location + range.length > suffixStartIndex {
            return false
        }
        
        return true
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        guard isChecked && !suffix.isEmpty else { return true }
        textField.text = suffix
        return false
    }
    
    private func updateButtonImage() {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let imageName = isChecked ? "checkmark.circle.fill" : "circle"
        let image = UIImage(systemName: imageName, withConfiguration: configuration)
        checkboxButton.setImage(image, for: .normal)
    }
    
    private func setup() {
        checkboxButton.tintColor = .systemBlue
        checkboxButton.imageView?.contentMode = .scaleAspectFit
        checkboxButton.setContentHuggingPriority(.required, for: .horizontal)
        checkboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        checkboxButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkboxButton.widthAnchor.constraint(equalToConstant: 22),
            checkboxButton.heightAnchor.constraint(equalToConstant: 22)
        ])
        checkboxButton.addTarget(self, action: #selector(toggleCheckbox), for: .touchUpInside)
        
        label.text = NSLocalizedString("Append Team ID", comment: "")
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .label
        label.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleCheckbox))
        label.addGestureRecognizer(tap)
        
        let stack = UIStackView(arrangedSubviews: [checkboxButton, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        
        updateButtonImage()
    }
    
    @objc func toggleCheckbox() {
        isChecked.toggle()
    }
}
