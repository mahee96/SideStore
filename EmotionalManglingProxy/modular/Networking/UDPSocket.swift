//
//  UDPSocket.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation

class UDPSocket {
    private var socketFileDescriptor: Int32
    private var timeout: Int = 1000
    private let logger = LoggerService.shared.createLogger(category: "UDPSocket")
    
    init(port: UInt16) throws {
        socketFileDescriptor = socket(AF_INET, SOCK_DGRAM, 0)
        if socketFileDescriptor < 0 {
            throw SocketError.failedToCreate
        }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(socketFileDescriptor, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if bindResult < 0 {
            Darwin.close(socketFileDescriptor)
            throw SocketError.failedToBind
        }
    }
    
    func setTimeout(_ timeoutMs: Int) {
        self.timeout = timeoutMs
        
        var tv = timeval()
        tv.tv_sec = __darwin_time_t(timeoutMs / 1000)
        tv.tv_usec = __darwin_suseconds_t((timeoutMs % 1000) * 1000)
        
        setsockopt(socketFileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }
    
    func send(data: Data, to host: String, port: UInt16) throws {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        
        let hostCString = host.cString(using: .utf8)!
        let conversionResult = hostCString.withUnsafeBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            return inet_pton(AF_INET, baseAddress, &addr.sin_addr)
        }
        
        if conversionResult <= 0 {
            throw SocketError.invalidAddress
        }
        
        let sendResult = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.sendto(socketFileDescriptor, bytes.baseAddress, bytes.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        
        if sendResult < 0 {
            throw SocketError.failedToSend
        }
    }

    func receive(timeout: Int? = nil) throws -> Data {
        if let timeout = timeout {
            setTimeout(timeout)
        }
        
        var buffer = [UInt8](repeating: 0, count: 2048)
        var addr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let recvResult = withUnsafeMutablePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.recvfrom(socketFileDescriptor, &buffer, buffer.count, 0, sockaddrPtr, &addrLen)
            }
        }
        
        if recvResult < 0 {
            throw SocketError.failedToReceive
        }
        
        return Data(buffer[0..<Int(recvResult)])
    }
    
    // Update other methods to use socketFileDescriptor instead of socket
    deinit {
        Darwin.close(socketFileDescriptor)
    }
    
    enum SocketError: Error {
        case failedToCreate
        case failedToBind
        case failedToSend
        case failedToReceive
        case invalidAddress
    }
}
