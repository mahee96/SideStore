//
//  TunError.swift
//  AltStore
//
//  Created by Magesh K on 02/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation
import Darwin

// MARK: - Tun Error

let SYSPROTO_CONTROL: Int32 = 2
let AF_SYS_CONTROL: Int32 = 2

enum TunError: Error {
    case invalidTunnelName
    case socketCreation(String)
    case ioctl(String)
    case connect(String)
    case fcntl(String)
    case getSockOpt(String)
    case ifaceRead(String)
}

// MARK: - Constants

/// The control name for utun devices.
let CTRL_NAME: [UInt8] = Array("com.apple.net.utun_control".utf8)

// These constants come directly from the original Rust code.
let CTLIOCGINFO: UInt64 = 0x00000000c0644e03
let SIOCGIFMTU: UInt64 = 0x00000000c0206933
let UTUN_OPT_IFNAME: Int32 = 2

// MARK: - C Struct Equivalents

/// Equivalent of the Rust `ctl_info` structure.
struct ctl_info {
    var ctl_id: UInt32 = 0
    var ctl_name: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0
    )
}

/// We only need the MTU member from the union. (Other members are omitted.)
struct IfrIfru {
    var ifru_mtu: Int32 = 0
}

/// Equivalent of the C `ifreq` structure.
struct ifreq {
    var ifr_name: (
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var ifr_ifru: IfrIfru = IfrIfru()
}

/// The sockaddr_ctl structure used to connect to the utun interface.
struct sockaddr_ctl {
    var sc_len: UInt8 = 0
    var sc_family: UInt8 = 0
    var ss_sysaddr: UInt16 = 0
    var sc_id: UInt32 = 0
    var sc_unit: UInt32 = 0
    var sc_reserved: (UInt32, UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
}

// MARK: - TunSocket

/// A Swift port of the Rust `TunSocket` implementation.
class TunSocket {
    let fd: Int32!

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        close(fd)
    }

    /// Returns the underlying file descriptor.
    func asRawFd() -> Int32 {
        return fd
    }

    /// Parses a tunnel name (which must start with "utun") and returns the index.
    static func parseUtunName(_ name: String) throws -> UInt32 {
        guard name.hasPrefix("utun") else {
            throw TunError.invalidTunnelName
        }
        let idxStr = String(name.dropFirst(4))
        if idxStr.isEmpty {
            return 0
        } else if let idx = UInt32(idxStr) {
            return idx + 1
        } else {
            throw TunError.invalidTunnelName
        }
    }

    /// Writes the given data preceded by a four-byte header (with address family `af`).
    func write(src: Data, af: UInt8) -> Int {
        var hdr: [UInt8] = [0, 0, 0, af]
        var iovecs = [iovec]()

        hdr.withUnsafeBytes { hdrPtr in
            iovecs.append(iovec(iov_base: UnsafeMutableRawPointer(mutating: hdrPtr.baseAddress), iov_len: hdr.count))
        }
        src.withUnsafeBytes { srcPtr in
            iovecs.append(iovec(iov_base: UnsafeMutableRawPointer(mutating: srcPtr.baseAddress), iov_len: src.count))
        }

        var msg = msghdr()
        msg.msg_name = nil
        msg.msg_namelen = 0
        let written = iovecs.withUnsafeMutableBufferPointer { buffer -> ssize_t in
            msg.msg_iov = buffer.baseAddress
            msg.msg_iovlen = Int32(__darwin_natural_t(buffer.count))
            msg.msg_control = nil
            msg.msg_controllen = 0
            msg.msg_flags = 0
            return sendmsg(fd, &msg, 0)
        }
        return (written == -1) ? 0 : Int(written)
    }

    /// Creates and returns a new TunSocket by connecting to the utun control.
    convenience init(name: String) throws {
        let idx = try TunSocket.parseUtunName(name)
        let sockfd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL)
        if sockfd == -1 {
            throw TunError.socketCreation(String(cString: strerror(errno)))
        }

        var info = ctl_info()
        // Copy CTRL_NAME into info.ctl_name.
        withUnsafeMutableBytes(of: &info.ctl_name) { buf in
            let count = min(CTRL_NAME.count, buf.count)
            for i in 0..<count {
                buf[i] = CTRL_NAME[i]
            }
        }

        if ioctl(sockfd, UInt(CTLIOCGINFO), &info) < 0 {
            close(sockfd)
            throw TunError.ioctl(String(cString: strerror(errno)))
        }

        var addr = sockaddr_ctl()
        addr.sc_len = UInt8(MemoryLayout<sockaddr_ctl>.size)
        addr.sc_family = UInt8(AF_SYSTEM)
        addr.ss_sysaddr = UInt16(AF_SYS_CONTROL)
        addr.sc_id = info.ctl_id
        addr.sc_unit = idx
        // sc_reserved is already zeroed

        var addrCopy = addr
        let ret = withUnsafePointer(to: &addrCopy) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                connect(sockfd, sockAddr, socklen_t(MemoryLayout<sockaddr_ctl>.size))
            }
        }
        if ret < 0 {
            close(sockfd)
            let errString = String(cString: strerror(errno)) + " (did you run with sudo?)"
            throw TunError.connect(errString)
        }
        self.init(fd: sockfd)
    }

    /// Sets the file descriptor to non-blocking mode.
    func setNonBlocking() throws -> TunSocket {
        let flags = fcntl(fd, F_GETFL, 0)
        if flags == -1 {
            throw TunError.fcntl(String(cString: strerror(errno)))
        }
        if fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1 {
            throw TunError.fcntl(String(cString: strerror(errno)))
        }
        return self
    }

    /// Retrieves the name of the tunnel interface.
    func name() throws -> String {
        var tunnelName = [CChar](repeating: 0, count: 256)
        var tunnelNameLen = socklen_t(tunnelName.count)
        let ret = tunnelName.withUnsafeMutableBufferPointer { buffer -> Int32 in
            return withUnsafeMutablePointer(to: &tunnelNameLen) { lenPtr in
                getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, buffer.baseAddress, lenPtr)
            }
        }
        if ret < 0 || tunnelNameLen == 0 {
            throw TunError.getSockOpt(String(cString: strerror(errno)))
        }
        return String(cString: tunnelName)
    }

    /// Retrieves the current MTU value.
    func mtu() throws -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_IP)
        if sock == -1 {
            throw TunError.socketCreation(String(cString: strerror(errno)))
        }
        defer { close(sock) }
        let ifaceName = try name()
        var ifr = ifreq()
        // Copy the interface name into ifr.ifr_name.
        withUnsafeMutableBytes(of: &ifr.ifr_name) { buffer in
            let cstr = ifaceName.utf8CString
            let count = min(cstr.count, buffer.count)
            for i in 0..<count {
                buffer[i] = UInt8(cstr[i])
            }
        }
        if ioctl(sock, UInt(Int32(SIOCGIFMTU)), &ifr) < 0 {
            throw TunError.ioctl(String(cString: strerror(errno)))
        }
        return Int(ifr.ifr_ifru.ifru_mtu)
    }

    /// Writes an IPv4 packet.
    func write4(src: Data) -> Int {
        return write(src: src, af: UInt8(AF_INET))
    }

    /// Writes an IPv6 packet.
    func write6(src: Data) -> Int {
        return write(src: src, af: UInt8(AF_INET6))
    }

    /// Reads a packet from the tunnel.
    ///
    /// The first four bytes (the header) are stripped off.
    func read(into dst: inout Data) throws -> Data {
        var hdr = [UInt8](repeating: 0, count: 4)
        
        var localHdr = hdr
        // Make a local copy of hdr to avoid overlapping mutable accesses.
        let hdrIovec: iovec = localHdr.withUnsafeMutableBytes { hdrPtr in
            var hdr = hdr
            return iovec(iov_base: hdrPtr.baseAddress, iov_len: hdr.count)
        }
        var localDst = dst
        let dstIovec: iovec = localDst.withUnsafeMutableBytes { dstPtr in
            var dst = dst
            return iovec(iov_base: dstPtr.baseAddress, iov_len: dst.count)
        }
        
        var iovecs = [hdrIovec, dstIovec]
        
        var msg = msghdr(
            msg_name: nil,
            msg_namelen: 0,
            msg_iov: nil,
            msg_iovlen: 0,
            msg_control: nil,
            msg_controllen: 0,
            msg_flags: 0
        )
        
        let bytesRead = iovecs.withUnsafeMutableBufferPointer { buffer -> ssize_t in
            msg.msg_iov = buffer.baseAddress
            msg.msg_iovlen = Int32(__darwin_natural_t(buffer.count))
            return recvmsg(fd, &msg, 0)
        }
        
        if bytesRead == -1 {
            throw TunError.ifaceRead(String(cString: strerror(errno)))
        } else if bytesRead <= 4 {
            return Data() // no payload
        } else {
            let payloadLength = Int(bytesRead) - 4
            return dst.subdata(in: 0..<payloadLength)
        }
    }
}
