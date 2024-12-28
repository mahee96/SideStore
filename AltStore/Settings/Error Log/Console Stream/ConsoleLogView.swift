//
//  ConsoleLogView.swift
//  AltStore
//
//  Created by Magesh K on 25/11/24.
//  Copyright © 2024 SideStore. All rights reserved.
//
//

import SwiftUI

class ConsoleLogger: ObservableObject {
    
    @Published var logBuffer: String = ""
    
    private static let CONSOLE_LOGS_DIRECTORY = "ConsoleLogs"
    private static let CONSOLE_LOG_NAME_PREFIX = "console"
    private static let CONSOLE_LOG_EXTN = ".log"
    
    private let bufferSize: Int
    
    // Need to defer the intialization and use lazy property
    // coz the self is captured in onUpdate and self is not available until all stored properties are inialized
    private lazy var consoleCapture: BufferedConsoleLogger<UnBufferedMemoryLogStream> = {
        let logFileHandle = Self.createLogFileHandle()
        let fileOutputStream = FileOutputStream(logFileHandle)
        let memoryLogStream = UnBufferedMemoryLogStream(fileOutputStream: fileOutputStream, bufferSize: bufferSize, onUpdate: onUpdate)
        return BufferedConsoleLogger(stream: memoryLogStream)
    }()
    
    init(bufferSize: Int = 1024) {
        self.bufferSize = bufferSize
        // This explicity access to consoleCapture in the init() is required
        // to trigger the lazy initialization within init itself
        consoleCapture.startCapturing()
    }
    
    private static func createLogFileHandle() -> FileHandle {
        // create a directory for console logs
        let docsDir = FileManager.default.documentsDirectory
        let consoleLogsDir = docsDir.appendingPathComponent(CONSOLE_LOGS_DIRECTORY)
        if !FileManager.default.fileExists(atPath: consoleLogsDir.path) {
            try! FileManager.default.createDirectory(at: consoleLogsDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        // get current timestamp
        let currentTime = Date()
        let dateTimeStamp = getDateInTimeStamp(date: currentTime)
        
        // create a log file with the current timestamp
        let logName = "\(CONSOLE_LOG_NAME_PREFIX)-\(dateTimeStamp)\(CONSOLE_LOG_EXTN)"
        let logFileURL = consoleLogsDir.appendingPathComponent(logName)
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }
        
        // return the file handle
        return try! FileHandle(forWritingTo: logFileURL)
    }
    
    private static func getDateInTimeStamp(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss" // Format: 20241228_142345
        return formatter.string(from: date)
    }
    
    func onUpdate(_ data: String) {
        DispatchQueue.main.async { [weak self] in
            self?.logBuffer = data
        }
    }
    
    func stopCapturing() {
        consoleCapture.stopCapturing()
    }
}


struct ConsoleLogView: View {
    
    @StateObject private var logger = ConsoleLogger(bufferSize: 100)
    
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                logContent
                Divider()
                toolbarContent
            }
            .navigationTitle("minimuxer")
            .navigationBarTitleDisplayMode(.inline)
//            .onAppear {
//                logger.startCapturing()
//            }
            .onDisappear {
                logger.stopCapturing()
            }
        }
        .onChange(of: presentationMode.wrappedValue.isPresented) { isPresented in
            if !isPresented {
                logger.stopCapturing()
            }
        }
    }

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(logger.logBuffer)
                    .font(.custom("SFMono-Regular", size: 14))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.black)
                    .cornerRadius(8)
                    .onChange(of: logger.logBuffer) { _ in
                        proxy.scrollTo(9999, anchor: .bottom) // Scroll to a high number to always go to the bottom
                    }
            }
        }
    }

    private var toolbarContent: some View {
        HStack {
//            shareButton
            Spacer()
            closeButton
        }
        .padding()
        .background(Color(UIColor.systemGray6))
    }

//    private var shareButton: some View {
//        SwiftUI.Button(action: shareLogs) {
//            Image(systemName: "square.and.arrow.up")
//                .font(.title2)
//                .foregroundColor(.blue)
//        }
//    }

    private var closeButton: some View {
        SwiftUI.Button(action: {
            logger.stopCapturing()
            presentationMode.wrappedValue.dismiss()
        }) {
            Image(systemName: "xmark")
                .font(.title2)
                .foregroundColor(.blue)
        }
    }

//    private func shareLogs() {
//        let logsText = logs.compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n")
//        let activityVC = UIActivityViewController(activityItems: [logsText], applicationActivities: nil)
//        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
//           let rootVC = windowScene.windows.first?.rootViewController {
//            rootVC.present(activityVC, animated: true, completion: nil)
//        }
//    }
}

class UnBufferedMemoryLogStream: OutputStream {
    private let fileOutputStream: FileOutputStream
    private let textBuffer: FixedSizeTextBuffer
    private let updateHandler: (String) -> Void
    
    init(fileOutputStream: FileOutputStream, bufferSize: Int, onUpdate: @escaping (String) -> Void) {
        self.fileOutputStream = fileOutputStream
        self.textBuffer = FixedSizeTextBuffer(maxSize: bufferSize)
        self.updateHandler = onUpdate
    }
    
    func write(_ data: Data) {
        // Write to file
        fileOutputStream.write(data)
        
        // Write to buffer
        if let text = String(data: data, encoding: .utf8) {
            textBuffer.append(text)
            // Notify the view about the updated buffer
            updateHandler(textBuffer.content)
        }
    }
    
    func flush() {
        fileOutputStream.flush()
    }
    
    func close() {
        fileOutputStream.close()
    }
}

protocol TextBuffer{
    func append(_ text: String)
}
    
class AbstractTextBuffer: TextBuffer{
    var buffer: String = ""
    
    // swift doesn't have abstract keyword :(
    public required init(){}
        
    func append(_ text: String){
        // Append the new text
        buffer.append(text)
    }
}

class FixedSizeTextBuffer: AbstractTextBuffer {
    private let maxSize: Int
    
    public init(maxSize: Int) {
        self.maxSize = maxSize
        super.init()
    }
    
    public required init() {
        fatalError("init() has not been implemented")
    }
    
    // Append text to the buffer
    public override func append(_ text: String) {
        let totalSize = buffer.count + text.count
        
        // Only remove excess if the total size exceeds maxSize
        if totalSize > maxSize {
            let excess = totalSize - maxSize
            let safeExcess = min(excess, buffer.count)
            buffer.removeFirst(safeExcess)
        }
        
        // Append the new text
        buffer.append(text)
    }
    
    // Get the current content of the buffer
    var content: String {
        return buffer
    }
    
    // Clear the buffer
    func clear() {
        buffer = ""
    }
}

class AppendingTextBuffer: TextBuffer{
    public var buffer: String = ""
    
    // Append text to the buffer
    func append(_ text: String) {
        // Append the new text
        buffer.append(text)
    }
    
    // Get the current content of the buffer
    var content: String {
        return buffer
    }
    
    // Clear the buffer
    func clear() {
        buffer = ""
    }
}
