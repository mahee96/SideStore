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

struct NetInfo: Hashable {
    let name: String
    let host: UInt32
    let mask: UInt32
    
    init(name: String, host: UInt32, mask: UInt32) {
        self.name = name
        self.host = host
        self.mask = mask
    }
    
    init?(_ ifaddr: ifaddrs) {
        guard let ianame = String(utf8String: ifaddr.ifa_name) else { return nil }
        self = .init(name: ianame, host: socktouint(&ifaddr.ifa_addr.pointee), mask: socktouint(&ifaddr.ifa_netmask.pointee))
    }
    
    var minIP: UInt32 { host &  mask }
    var maxIP: UInt32 { host | ~mask }
    var hostIP: String { uti(host) ?? "nil" }
    var maskIP: String { uti(mask) ?? "nil" }
}

final class IfManager: Sendable {
    static let shared = IfManager()
    nonisolated(unsafe) private(set) var addrs: Set<NetInfo> = Set()
    
    init() {
        self.addrs = IfManager.update()
    }
    
    public func update() {
        addrs = IfManager.update()
    }
    
    private static func update() -> Set<NetInfo> {
        var addrs = Set<NetInfo>()
        var head: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&head) == 0, let first = head else { return addrs }
        defer { freeifaddrs(head) }
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = first
        while let next = ifaddr {
            // we only want v4 interfaces that aren't loopback and aren't masked 255.255.255.255
            if (next.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET)),
               (Int32(next.pointee.ifa_flags) & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING),
               let info = NetInfo(next.pointee),
               info.mask != 0xffffffff {
                addrs.insert(info)
            }
            ifaddr = next.pointee.ifa_next
        }
        return addrs
    }
    
    var nextLAN: NetInfo? {
        addrs.first { $0.name.starts(with: "en") }
    }
    
    var nextProbableSideVPN: NetInfo? {
        // try old 10.7.0.0 first, then fallback to next v4
        // user should only be connected to StosVPN/LocalDevVPN
        addrs.first { $0.host == 168230912 || $0.name.starts(with: "utun") }
    }
    
    var sideVPNPatched: Bool {
        nextLAN?.mask == nextProbableSideVPN?.mask &&
        nextLAN?.maxIP == nextProbableSideVPN?.maxIP
    }
}

