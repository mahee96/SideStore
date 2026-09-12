import SwiftUI
import UniformTypeIdentifiers

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct BackupAndRestoreView: View {
    @State private var showingImportFilePicker = false
    @State private var importedData: Data? = nil
    @State private var showingImportPasswordAlert = false
    @State private var importFilePassword = ""
    
    @State private var importedAccount: ImportedAccount? = nil
    @State private var showingApplePasswordAlert = false
    @State private var applePasswordInput = ""
    
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingMessageAlert = false
    @State private var exportFileURL: URL? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: Account, Certificate, & Pairing Data
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("ACCOUNT, CERTIFICATE, & PAIRING DATA"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button(action: {
                            showingImportFilePicker = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(localized("Import Account"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(action: {
                            presentExportAlert()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(localized("Export Account"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                
                #if DEBUG
                // Section 2: Sources Data
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("SOURCES DATA"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button(action: {
                            print("[BackupAndRestoreView] Import Sources tapped")
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(localized("Import Sources"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(action: {
                            print("[BackupAndRestoreView] Export Sources tapped")
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(localized("Export Sources"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle(localized("Backup & Restore"))
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .sheet(isPresented: $showingImportFilePicker) {
            DocumentPickerView(contentTypes: [UTType(filenameExtension: "sideconf") ?? .data]) { url in
                guard let url = url else { return }
                do {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    self.importedData = data
                    self.importFilePassword = ""
                    self.showingImportPasswordAlert = true
                } catch {
                    showAlert(title: localized("Import Error"), message: error.localizedDescription)
                }
            }
        }
        .alert(localized("Decrypt Backup"), isPresented: $showingImportPasswordAlert) {
            SecureField(localized("File Password"), text: $importFilePassword)
            SwiftUI.Button(localized("Decrypt")) {
                performImportDecrypt()
            }
            SwiftUI.Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("Enter the password used to encrypt this backup file."))
        }
        .alert(localized("Apple ID Password"), isPresented: $showingApplePasswordAlert) {
            SecureField(localized("Password"), text: $applePasswordInput)
            SwiftUI.Button(localized("Sign In")) {
                performAppleSignIn()
            }
            SwiftUI.Button(localized("Cancel"), role: .cancel) {}
        } message: {
            if let email = importedAccount?.email {
                Text(localized("Please enter Apple ID password for \(email) to complete sign-in."))
            } else {
                Text(localized("Please enter your Apple ID password to complete sign-in."))
            }
        }
        .alert(alertTitle, isPresented: $showingMessageAlert) {
            SwiftUI.Button(localized("OK"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: Binding<Bool>(
            get: { exportFileURL != nil },
            set: { if !$0 { exportFileURL = nil } }
        )) {
            if let url = exportFileURL {
                ActivityViewController(activityItems: [url])
            }
        }
    }
    
    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    private func presentExportAlert() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        
        let alert = UIAlertController(title: localized("Export Account"), message: nil, preferredStyle: .alert)
        let alertVC = ExportAccountAlertViewController()
        alert.setValue(alertVC, forKey: "contentViewController")
        
        let exportAction = UIAlertAction(title: localized("Export"), style: .default) { _ in
            let filePassword = alertVC.passwordTextField.text ?? ""
            let includeApplePassword = alertVC.isIncludePasswordChecked
            
            guard !filePassword.isEmpty else {
                showAlert(title: localized("Export Error"), message: localized("File password cannot be empty."))
                return
            }
            
            do {
                let encryptedData = try ImportExport.exportAccount(password: filePassword, includeApplePassword: includeApplePassword)
                guard AuthManager.shared.currentAppleID != nil else { return }
                
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent(AppConstants.accountConfigurationFileName)
                try encryptedData.write(to: fileURL)
                
                DispatchQueue.main.async {
                    self.exportFileURL = fileURL
                }
            } catch {
                showAlert(title: localized("Export Error"), message: error.localizedDescription)
            }
        }
        
        let cancelAction = UIAlertAction(title: localized("Cancel"), style: .cancel)
        
        alert.addAction(exportAction)
        alert.addAction(cancelAction)
        
        top.present(alert, animated: true)
    }
    
    private func performImportDecrypt() {
        guard let data = importedData, !importFilePassword.isEmpty else { return }
        do {
            let account = try ImportExport.importAccount(data, filePassword: importFilePassword)
            self.importedAccount = account
            
            if let pass = account.password, !pass.isEmpty {
                showAlert(title: localized("Account Imported"), message: localized("Account \(account.email) imported successfully!"))
            } else {
                self.applePasswordInput = ""
                self.showingApplePasswordAlert = true
            }
        } catch {
            showAlert(title: localized("Import Error"), message: error.localizedDescription)
        }
    }
    
    private func performAppleSignIn() {
        guard let account = importedAccount, !applePasswordInput.isEmpty else { return }
        AuthManager.shared.password = applePasswordInput
        showAlert(title: localized("Account Imported"), message: localized("Account \(account.email) imported successfully!"))
    }

    private func showAlert(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showingMessageAlert = true
    }
}

#if !os(tvOS)
struct DocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
#else
struct DocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        DispatchQueue.main.async {
            TVWebFileTransferManager.shared.startImport(
                contentTypes: contentTypes,
                title: localized("Import File"),
                presentingVC: vc
            ) { url in
                onPick(url)
            }
        }
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#endif
