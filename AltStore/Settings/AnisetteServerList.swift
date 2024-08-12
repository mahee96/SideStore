//
//  AnisetteServerList.swift
//  SideStore
//
//  Created by ny on 6/18/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import UIKit
import SwiftUI
import AltStoreCore

typealias SUIButton = SwiftUI.Button

// MARK: - AnisetteServerData
struct AnisetteServerData: Codable {
    let servers: [Server]
}

// MARK: - Server
struct Server: Codable {
    var name: String
    var address: String
}

class AnisetteViewModel: ObservableObject {
    @Published var selected: String = ""

    @Published var source: String = "https://servers.sidestore.io/servers.json"
    @Published var servers: [Server] = []
    
    func getListOfServers() {
        guard let url = URL(string: source) else { return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                return
            }
            if let data = data {
                do {
                    let decoder = Foundation.JSONDecoder()
                    let servers = try decoder.decode(AnisetteServerData.self, from: data)
                    DispatchQueue.main.async {
                        self.servers = servers.servers
                    }
                } catch {
                    // Handle decoding error
                    print("Failed to decode JSON: \(error)")
                }
            }
        }.resume()
    }
}

struct AnisetteServers: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var viewModel: AnisetteViewModel = AnisetteViewModel()
    @State var selected: String? = nil
    var errorCallback: () -> ()

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
                .onAppear {
                    viewModel.getListOfServers()
                }
            VStack {
                if #available(iOS 16.0, *) {
                    SwiftUI.List($viewModel.servers, id: \.address, selection: $selected) { server in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(server.name.wrappedValue)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("\(server.address.wrappedValue)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selected != nil {
                                if server.address.wrappedValue == selected {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                        .onAppear {
                                            UserDefaults.standard.menuAnisetteURL = server.address.wrappedValue
                                            print(UserDefaults.synchronize(.standard)())
                                            print(UserDefaults.standard.menuAnisetteURL)
                                            print(server.address.wrappedValue)
                                        }
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                        .shadow(color: Color.gray.opacity(0.4), radius: 5, x: 0, y: 5)
                        .listRowSeparatorTint(.white)
                        .listRowBackground(Color(UIColor.systemBackground).ignoresSafeArea())
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listRowBackground(Color(UIColor.systemBackground).ignoresSafeArea())
                    
                } else {
                    List(selection: $selected) {
                        ForEach($viewModel.servers, id: \.name) { server in
                            VStack {
                                HStack {
                                    Text("\(server.name.wrappedValue)")
                                        .foregroundColor(.primary)
                                        .frame(alignment: .center)
                                    Text("\(server.address.wrappedValue)")
                                        .foregroundColor(.secondary)
                                        .frame(alignment: .center)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)
                    }
                    .listStyle(.plain)
                    // Fallback on earlier versions
                }
                
                VStack(spacing: 16) {
                    // TextField with gray background
                    TextField("Anisette Server List", text: $viewModel.source)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray))
                        .foregroundColor(.white)
                        .frame(height: 60)
                        .shadow(color: Color.gray.opacity(0.4), radius: 10, x: 0, y: 5)
                        .onChange(of: viewModel.source) { newValue in
                            UserDefaults.standard.menuAnisetteList = newValue
                            viewModel.getListOfServers()
                        }

                    // Back and Refresh Buttons next to each other
                    HStack(spacing: 16) {
                        SUIButton(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Text("Back")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                        .foregroundColor(.white)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 10, x: 0, y: 5)

                        SUIButton(action: {
                            viewModel.getListOfServers()
                        }) {
                            Text("Refresh Servers")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                        .foregroundColor(.white)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 10, x: 0, y: 5)
                    }

                    // Reset Button below Back and Refresh
                    SUIButton(action: {
                        #if !DEBUG
                        if Keychain.shared.adiPb != nil {
                            Keychain.shared.adiPb = nil
                        }
                        #endif
                        print("Cleared adi.pb from keychain")
                        errorCallback()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Reset adi.pb")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.red))
                    .foregroundColor(.white)
                    .shadow(color: Color.red.opacity(0.4), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal)
            }
        }
        .navigationBarHidden(true) // Hide the navigation bar if you don't need it
        .navigationTitle("") // Remove title to avoid extra space
    }
}
