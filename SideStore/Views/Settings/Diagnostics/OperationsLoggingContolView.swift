//
//  OperationsLoggingContolView.swift
//  SideStore
//
//  Created by Magesh K on 14/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import SwiftUI
@preconcurrency import AltStoreCore

private let pipelineStepToggles: [(name: String, step: PipelineStep)] = [
    ("Backup App Data",                         .backupAppData),
    ("Cache App",                               .cacheApp),
    ("Change App Icon",                         .changeAppIcon),
    ("Clean Staged App",                        .cleanStagedApp),
    ("Deactivate App",                          .deactivateApp),
    ("Download App",                            .downloadApp),
    ("Enable JIT",                              .enableJIT),
    ("Export Resigned App",                     .exportResignedApp),
    ("Fetch Provisioning Profiles (Install)",   .fetchProvisioningProfilesInstall),
    ("Fetch Provisioning Profiles (Refresh)",   .fetchProvisioningProfilesRefresh),
    ("Install App",                             .installApp),
    ("Preflight Checks",                        .preflightChecks),
    ("Prepare App Extension Bundle IDs",        .prepareAppExtensionBundleIDs),
    ("Refresh App",                             .refreshApp),
    ("Remove App",                              .removeApp),
    ("Remove App Extensions",                   .removeAppExtensions),
    ("Remove Backup Data",                      .removeBackupData),
    ("Resign App",                              .resignApp),
    ("Restore App Data",                        .restoreAppData),
    ("Send App",                                .sendApp),
    ("Stage App",                               .stageApp),
    ("Stage Backup App",                        .stageBackupApp),
    ("Update App Certificate",                  .updateAppCertificate),
    ("User Customization",                      .userCustomization),
    ("Verify App",                              .verifyApp),
    ("Verify Certificate",                      .verifyCertificate),
]

private let standaloneStepToggles: [(name: String, step: StandaloneStep)] = [
    ("Authentication",                          .authentication),
    ("Background Refresh Apps",                 .backgroundRefreshApps),
    ("Clear App Cache",                         .clearAppCache),
    ("Fetch Anisette Data",                     .fetchAnisetteData),
    ("Fetch App IDs",                           .fetchAppIDs),
    ("Fetch Source",                            .fetchSource),
    ("Schedule Expiration Warning",             .scheduleExpirationWarningNotification),
]

struct OperationsLoggingControlView: View {
    let TITLE = "Operations Logging"

    @ObservedObject private var viewModel = OperationsLoggingViewModel()

    var body: some View {
        NavigationView {
            List {
                Section(header: sectionHeader("Standalone Steps")) {
                    ForEach(standaloneStepToggles, id: \.name) { entry in
                        stepToggle(entry.name, step: entry.step)
                    }
                }

                Section(header: sectionHeader("Pipeline Steps")) {
                    ForEach(pipelineStepToggles, id: \.name) { entry in
                        stepToggle(entry.name, step: entry.step)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(TITLE)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundColor(.primary)
    }

    private func stepToggle(_ title: String, step: some OperationStep) -> some View {
        Toggle(title, isOn: Binding(
            get: { OperationsLoggingControl.isStepLoggingEnabled(for: step) },
            set: { value in
                OperationsLoggingControl.setStepLoggingEnabled(for: step, value: value)
                viewModel.refresh()
            }
        ))
        .padding(.vertical, 2)
    }
}

private final class OperationsLoggingViewModel: ObservableObject {
    func refresh() {
        objectWillChange.send()
    }
}
