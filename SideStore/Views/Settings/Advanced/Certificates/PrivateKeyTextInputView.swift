//
//  PrivateKeyTextInputView.swift
//  SideStore
//
//  Created by Magesh K on 2026-07-03.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import SideSign

struct PrivateKeyTextInputView: View {
    @Binding var text: String
    let cert: ALTX509Certificate
    let viewModel: CertificatesViewModel
    let allowedKeyImportTypes: [UTType]
    var onCancel: () -> Void
    
    @State private var showFilePicker = false
    @State private var errorMessage: String? = nil
    @State private var isEditing = false
    @State private var showSuccessAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                Text(localized("Paste your PEM-formatted private key below, or import it from a text file."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top)
                
                PrivateKeyTextEditor(text: $text, isEditing: $isEditing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(4)
                    #if !os(tvOS)
                    .background(Color(.secondarySystemBackground))
                    #else
                    .background(Color.white.opacity(0.1))
                    #endif
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                HStack(spacing: 12) {
                    SwiftUI.Button {
                        #if !os(tvOS)
                        showFilePicker = true
                        #else
                        if let topVC = UIApplication.shared.topViewController() {
                            TVWebFileTransferManager.shared.startImport(
                                acceptedExtensions: ["pem", "key", "txt"],
                                title: localized("Import PEM Private Key File"),
                                presentingVC: topVC
                            ) { fileURL in
                                guard let fileURL = fileURL else { return }
                                do {
                                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                                    text = content
                                    isEditing = false
                                    errorMessage = nil
                                } catch {
                                    errorMessage = localized("Failed to read file: \(error.localizedDescription)")
                                }
                            }
                        }
                        #endif
                    } label: {
                        Label(localized("Import from File"), systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    
                    SwiftUI.Button {
                        if let keyData = text.data(using: .utf8) {
                            do {
                                let formattedKey = try viewModel.validateAndFormatPrivateKey(data: keyData)
                                let signableCert = ALTCertificate(x509: cert, privateKey: formattedKey)
                                viewModel.saveLocalCertificate(signableCert)
                                viewModel.loadCertificates(presentingViewController: nil)
                                showSuccessAlert = true
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Text(localized("Add PEM Key"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(localized("Add Private Key"))
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        SwiftUI.Button(localized("Done")) {
                            isEditing = false
                        }
                    } else {
                        SwiftUI.Button {
                            onCancel()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            #if !os(tvOS)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: allowedKeyImportTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            let content = try String(contentsOf: url, encoding: .utf8)
                            text = content
                            isEditing = false
                            errorMessage = nil
                        } catch {
                            errorMessage = localized("Failed to read file: \(error.localizedDescription)")
                        }
                    }
                case .failure(let error):
                    errorMessage = localized("Failed to select file: \(error.localizedDescription)")
                }
            }
            #endif
            .alert(localized("Key Added"), isPresented: $showSuccessAlert) {
                SwiftUI.Button(localized("OK")) {
                    onCancel()
                }
            } message: {
                Text(localized("Key was added to certificate \(cert.name) (SN: \(cert.serialNumber))."))
            }
        }
    }
}
