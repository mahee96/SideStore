//
//  IfManager.swift
//  AltStore
//
//  Created by ny on 2/27/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Network

fileprivate func uti(_ uint: UInt32) -> String? {
    var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    var addr = in_addr(s_addr: uint.bigEndian)
    guard inet_ntop(AF_INET, &addr, &buf, UInt32(INET_ADDRSTRLEN)) != nil,
        let str = String(utf8String: buf) else { return nil }
    return str
}

fileprivate func socktouint(_ sock: inout sockaddr) -> UInt32 {
    var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    guard getnameinfo(&sock, socklen_t(sock.sa_len), &buf, socklen_t(buf.count), nil, socklen_t(0), NI_NUMERICHOST) == 0,
          let name = String(utf8String: buf) else {
        return 0
    }
    var addr = in_addr()
    guard name.withCString({ cString in
        inet_pton(AF_INET, cString, &addr)
    }) == 1 else { return 0 }
    return addr.s_addr.bigEndian
}

public struct NetInfo: Hashable, CustomStringConvertible {
    public let name: String
    public let hostIP: String
    public let destIP: String
    public let maskIP: String
    
    private let host: UInt32
    private let dest: UInt32
    private let mask: UInt32
    
    init(name: String, host: UInt32, dest: UInt32, mask: UInt32) {
        self.name = name
        self.host = host
        self.dest = dest
        self.mask = mask
        self.hostIP = uti(host) ?? "10.7.0.0"
        self.destIP = uti(dest) ?? "10.7.0.1"
        self.maskIP = uti(mask) ?? "255.255.255.0"
    }
    
    init?(_ ifaddr: ifaddrs) {
        guard
            let ianame = String(utf8String: ifaddr.ifa_name)
        else { return nil }
        
        let host = socktouint(&ifaddr.ifa_addr.pointee)
        let dest = socktouint(&ifaddr.ifa_dstaddr.pointee)
        let mask = socktouint(&ifaddr.ifa_netmask.pointee)
        
        self.init(name: ianame, host: host, dest: dest, mask: mask)
    }
    
    // computed networking values (still numeric internally)
    public var minIP: UInt32 { host & mask }
    public var maxIP: UInt32 { host | ~mask }
    
    public var minIPString: String { uti(minIP) ?? "nil" }
    public var maxIPString: String { uti(maxIP) ?? "nil" }
    
    public var description: String {
        "\(name) | ip=\(hostIP) dest=\(destIP) mask=\(maskIP) range=\(minIPString)-\(maxIPString)"
    }
}

final class IfManager: Sendable {
    public static let shared = IfManager()
    nonisolated(unsafe) private(set) var addrs: Set<NetInfo> = Set()

    private init() {
        self.addrs = IfManager.query()
    }

    
    public func query() {
        addrs = IfManager.query()
    }

    private static func query() -> Set<NetInfo> {
        var addrs = Set<NetInfo>()
        var head: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&head) == 0, let first = head else { return addrs }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            // we only want v4 interfaces that aren't loopback and aren't masked 255.255.255.255
            let entry = current.pointee
            let flags = Int32(entry.ifa_flags)

            let isIPv4 = entry.ifa_addr.pointee.sa_family == UInt8(AF_INET)
            let isActive = (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING)

            if isIPv4, isActive, let info = NetInfo(entry), info.maskIP != "255.255.255.255" {
                addrs.insert(info)
            }

            cursor = entry.ifa_next
        }
        return addrs
    }
    
    private var nextLAN: NetInfo? {
        addrs.first { $0.name.starts(with: "en") }
    }
    
    var nextProbableSideVPN: NetInfo? {
        // try old 10.7.0.1 first, then fallback to next v4
        // user should only be connected to StosVPN/LocalDevVPN
        addrs.first {
            $0.hostIP == "10.7.0.1" ||
            $0.name.starts(with: "utun")
        }
    }
    
    var sideVPNPatched: Bool {
        nextLAN?.maskIP == nextProbableSideVPN?.maskIP &&
        nextLAN?.maxIP == nextProbableSideVPN?.maxIP
    }
}

