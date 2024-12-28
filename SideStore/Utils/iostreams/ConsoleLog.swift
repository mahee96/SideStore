//
//  ConsoleLogView.swift
//  AltStore
//
//  Created by Magesh K on 25/11/24.
//  Copyright © 2024 SideStore. All rights reserved.
//
//

import SwiftUI

class ConsoleLog: ObservableObject {
    
    private static let CONSOLE_LOGS_DIRECTORY = "ConsoleLogs"
    private static let CONSOLE_LOG_NAME_PREFIX = "console"
    private static let CONSOLE_LOG_EXTN = ".log"
    
    private let bufferSize: Int
    
    // Need to defer the intialization and use lazy property
    // coz the self is captured in onUpdate and self is not available until all stored properties are inialized
    private lazy var consoleCapture: ConsoleLogger = {
        let logFileHandle = Self.createLogFileHandle()              // if statics are overriden invoke them via dynamic dispatch
        let fileOutputStream = FileOutputStream(logFileHandle)
        
        let memoryLogStream = UnBufferedMemoryLogStream(fileOutputStream: fileOutputStream, bufferSize: bufferSize, onUpdate: onUpdate)
//        return BufferedConsoleLogger(stream: memoryLogStream)
        return UnBufferedConsoleLogger(stream: memoryLogStream)
    }()
    
    init(bufferSize: Int = 1024) {
        self.bufferSize = bufferSize
        
        // This explicity access to consoleCapture in the init() is required
        // to trigger the lazy initialization and log construction within init itself
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

