//
//  ConsoleCapture.swift
//  AltStore
//
//  Created by Magesh K on 25/11/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import Foundation

protocol OutputStream {
    func write(_ data: Data)
    func flush()
    func close()
}

class FileOutputStream: OutputStream {
    private let fileHandle: FileHandle
    
    init(_ fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }
    
    func write(_ data: Data) {
        fileHandle.write(data)
    }
    
    func flush() {
        fileHandle.synchronizeFile()
    }
    
    func close() {
        fileHandle.closeFile()
    }
}

class BufferedConsoleLogger<T: OutputStream> {
    private var outPipe: Pipe?
    private var errPipe: Pipe?
    
    private var outputHandle: FileHandle?
    private var errorHandle:  FileHandle?
    
    private var originalStdout: Int32?
    private var originalStderr: Int32?
    
    private let ostream: T
    
    private let writeQueue = DispatchQueue(label: "async-write-queue")
    
    // Buffer size (bytes) and storage
    private let maxBufferSize: Int
    private var bufferedData = Data()
    
    init(stream: T, bufferSize: Int = 1024) {
        self.ostream = stream
        self.maxBufferSize = bufferSize
        // commented this line to let client ask for capturing explicitly instead of starting at init
//        startCapturing()
    }
    
    deinit {
        stopCapturing()
    }
    
//    private func startCapturing() {
    public func startCapturing() {                          // made it public coz, let client ask for capturing
        
        // if already initialized within current instance, bail out
        guard outPipe == nil, errPipe == nil else {
            return
        }
        
        // Create new pipes for stdout and stderr
        self.outPipe = Pipe()
        self.errPipe = Pipe()
        
        outputHandle = self.outPipe?.fileHandleForReading
        errorHandle = self.errPipe?.fileHandleForReading

        // Store original file descriptors
        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)
        
        // Redirect stdout and stderr to our pipes
        dup2(self.outPipe?.fileHandleForWriting.fileDescriptor ?? -1, STDOUT_FILENO)
        dup2(self.errPipe?.fileHandleForWriting.fileDescriptor ?? -1, STDERR_FILENO)

        // Setup readability handlers for raw data
        setupReadabilityHandler(for: outputHandle, isError: false)
        setupReadabilityHandler(for: errorHandle, isError: true)
    }

    private func setupReadabilityHandler(for handle: FileHandle?, isError: Bool) {
        handle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                self?.writeQueue.async {
                    self?.bufferedData.append(data)
                    
                    // Check if the buffer is full and flush
                    if self?.bufferedData.count ?? 0 >= self?.maxBufferSize ?? 0 {
                        self?.flushBuffer()
                    }
                }
                
                // Forward to original std stream
                if let originalFD = isError ? self?.originalStderr : self?.originalStdout {
                    data.withUnsafeBytes { (bufferPointer) -> Void in
                        if let baseAddress = bufferPointer.baseAddress, bufferPointer.count > 0 {
                            write(originalFD, baseAddress, bufferPointer.count)
                        }
                    }
                }
            }
        }
    }
    
    private func flushBuffer() {
        // Write all buffered data to the stream
        ostream.write(bufferedData)
        bufferedData.removeAll()
    }

    func stopCapturing() {
        // Flush buffer and close the file handles first
        flushBuffer()
        ostream.close()
        
        // Restore original stdout and stderr
        if let stdout = originalStdout {
            dup2(stdout, STDOUT_FILENO)
            close(stdout)
        }
        if let stderr = originalStderr {
            dup2(stderr, STDERR_FILENO)
            close(stderr)
        }
        
        // Clean up
        outPipe?.fileHandleForReading.readabilityHandler = nil
        errPipe?.fileHandleForReading.readabilityHandler = nil
        outPipe = nil
        errPipe = nil
        outputHandle = nil
        errorHandle = nil
        originalStdout = nil
        originalStderr = nil
    }
}
