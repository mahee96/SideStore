//
//  UDPSocket.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

class UDPSocket {
    public enum SocketError: Error {
        case failedToCreate
        case failedToBind
        case failedToSend
        case failedToReceive
        case invalidAddress
        case timeout
        case wouldBlock
        case addressInUse
    }
    
    private var socket: Int32 = -1
    
    init() throws {
        socket = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        if socket < 0 {
            throw SocketError.failedToCreate
        }
    }
    
    deinit {
        if socket >= 0 {
            Darwin.close(socket)
        }
    }
    
    func bind(to address: SocketAddress) throws {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(UInt16(address.port))
        addr.sin_addr.s_addr = inet_addr(address.host)
        
        let result = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                Darwin.bind(socket, addr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if result < 0 {
            if errno == EADDRINUSE {
                throw SocketError.addressInUse
            }
            throw SocketError.failedToBind
        }
    }
    
    func setReadTimeout(milliseconds: Int32) throws {
        var timeout = timeval()
        timeout.tv_sec = __darwin_time_t(milliseconds / 1000)
        timeout.tv_usec = __darwin_suseconds_t((milliseconds % 1000) * 1000)
        
        let result = setsockopt(
            socket,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        
        if result < 0 {
            throw SocketError.failedToCreate
        }
    }
    
    func sendTo(_ data: [UInt8], endpoint: SocketAddress) throws {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(UInt16(endpoint.port))
        addr.sin_addr.s_addr = inet_addr(endpoint.host)
        
        let result = data.withUnsafeBufferPointer { buffer in
            withUnsafePointer(to: addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    Darwin.sendto(
                        socket,
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        addr,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        
        if result < 0 {
            throw SocketError.failedToSend
        }
    }
    
    func receiveFrom(_ buffer: inout [UInt8]) throws -> (Int, SocketAddress) {
        var addr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let result = buffer.withUnsafeMutableBufferPointer { buffer in
            withUnsafeMutablePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    Darwin.recvfrom(
                        socket,
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        addr,
                        &addrLen
                    )
                }
            }
        }
        
        if result < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                throw SocketError.wouldBlock
            }
            if errno == ETIMEDOUT {
                throw SocketError.timeout
            }
            throw SocketError.failedToReceive
        }
        
        let ipAddress = String(cString: inet_ntoa(addr.sin_addr))
        let port = Int(CFSwapInt16BigToHost(addr.sin_port))
        
        return (Int(result), SocketAddress(host: ipAddress, port: port))
    }
}
