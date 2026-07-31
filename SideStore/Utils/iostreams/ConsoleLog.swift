//
//  ConsoleLog.swift
//  AltStore
//
//  Created by Magesh K on 25/11/24.
//  Copyright © 2024 SideStore. All rights reserved.
//
//

import Foundation

class ConsoleLog {
    private static let CONSOLE_LOGS_DIRECTORY = "ConsoleLogs"
    private static let CONSOLE_LOG_NAME_PREFIX = "console"
    private static let CONSOLE_LOG_EXTN = ".log"
    
    private lazy var consoleLogger: ConsoleLogger = {
        let logFileHandle = createLogFileHandle()!
        let fileOutputStream = FileOutputStream(
            fileHandle: logFileHandle,
            fileHandleProvider: { [weak self] in
                return self?.createLogFileHandle()
            },
            fileExistsProvider: { [weak self] in
                guard let self = self else { return false }
                return FileManager.default.fileExists(atPath: self.logFileURL.path)
            }
        )
        let syslogOutputStream = SyslogOutputStream()
        let compositeStream = CompositeOutputStream([fileOutputStream, syslogOutputStream])
        
        return UnBufferedConsoleLogger(stream: compositeStream)
    }()
    
    private func createLogFileHandle() -> FileHandle? {
        let parentDir = logFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }
        let handle = try? FileHandle(forWritingTo: logFileURL)
        handle?.seekToEndOfFile()
        return handle
    }
    
    private lazy var consoleLogsDir: URL = {
        // create a directory for console logs
        let docsDir = FileManager.default.documentsDirectory
        let consoleLogsDir = docsDir.appendingPathComponent(ConsoleLog.CONSOLE_LOGS_DIRECTORY)
        if !FileManager.default.fileExists(atPath: consoleLogsDir.path) {
            try! FileManager.default.createDirectory(at: consoleLogsDir, withIntermediateDirectories: true, attributes: nil)
        }
        return consoleLogsDir
    }()
    
    public lazy var logName: String = {
        logFileURL.lastPathComponent
    }()
    
    public lazy var logFileURL: URL = {
        // get current timestamp
        let currentTime = Date()
        let dateTimeStamp = DateTimeUtil.getDateInTimeStamp(date: currentTime)
        
        // create a log file with the current timestamp
        let logName = DateTimeUtil.getTimeStampSuffixedFileName(
            fileName: ConsoleLog.CONSOLE_LOG_NAME_PREFIX,
            timestamp: dateTimeStamp,
            extn: ConsoleLog.CONSOLE_LOG_EXTN
        )
        let logFileURL = consoleLogsDir.appendingPathComponent(logName)
        return logFileURL
    }()
    
    func startCapturing() {
        consoleLogger.startCapturing()
    }
    
    func stopCapturing() {
        consoleLogger.stopCapturing()
    }
}

