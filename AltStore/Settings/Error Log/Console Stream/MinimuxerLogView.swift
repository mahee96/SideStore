//
//  MinimuxerLogView.swift
//  AltStore
//
//  Created by Magesh K on 25/11/24.
//  Copyright © 2024 SideStore. All rights reserved.
//


import SwiftUI

struct MinimuxerLogView: View {
    @StateObject private var viewModel = LogViewModel()
    
    var body: some View {
        NavigationView {
            logScrollView
                .navigationTitle("Minimuxer Logs")
                .toolbar(content: {
                    ToolbarItem(placement: .cancellationAction, content: {
                        SwiftUI.Button(action: {
                            viewModel.stopObserving()
                        }) {
                            Text("Close")
                        }
                    })
                })
        }
        .onDisappear {
            viewModel.stopObserving()
        }
    }


    private var logScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                logLinesView
                    .padding()
            }
            .background(Color.black)
            .onChange(of: viewModel.logLines) { _ in
                scrollToLastLine(using: proxy)
            }
        }
    }

    private var logLinesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.logLines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption))
//                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func scrollToLastLine(using proxy: ScrollViewProxy) {
        if let lastIndex = viewModel.logLines.indices.last {
            proxy.scrollTo(viewModel.logLines[lastIndex], anchor: .bottom)
        }
    }

}

class LogViewModel: ObservableObject {
    @Published var logLines: [String] = []
    
    private var fileHandle: FileHandle?
    private var fileObserver: DispatchSourceFileSystemObject?
    private let logFileURL: URL
    
    init() {
        logFileURL = FileManager.default.documentsDirectory.appendingPathComponent("minimuxer.log")
        setupLogFile()
        startObservingLogFile()
    }
    
    deinit {
        stopObserving()
    }
    
    private func setupLogFile() {
        // Ensure the log file exists
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
    }
    
    func startObservingLogFile() {
        do {
            fileHandle = try FileHandle(forReadingFrom: logFileURL)
            fileHandle?.seekToEndOfFile() // Start observing at the end of the file
            
            if let fileDescriptor = fileHandle?.fileDescriptor {
                fileObserver = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fileDescriptor,
                    eventMask: .extend,
                    queue: DispatchQueue.global()
                )
                
                fileObserver?.setEventHandler { [weak self] in
                    self?.readNewLogLines()
                }
                
                fileObserver?.resume()
            }
        } catch {
            print("Failed to open log file: \(error)")
        }
    }
    
    func stopObserving() {
        fileObserver?.cancel()
        fileObserver = nil
        fileHandle?.closeFile()
        fileHandle = nil
    }
    
    private func readNewLogLines() {
        guard let fileHandle = fileHandle else { return }
        
        let newData = fileHandle.readDataToEndOfFile()
        if let newLog = String(data: newData, encoding: .utf8) {
            let newLines = newLog.components(separatedBy: .newlines).filter { !$0.isEmpty }
            DispatchQueue.main.async { [weak self] in
                self?.logLines.append(contentsOf: newLines)
            }
        }
    }
}

extension FileManager {
    var documentsDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
