//
//  YourViewController.swift
//  AltStore
//
//  Created by Magesh K on 01/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import EmotionalManglingProxy

class YourViewController: UIViewController {
    
    func startProxy() {
        let bindAddr = SocketAddress(host: "127.0.0.1", port: 51820)
        EmotionalDamage.start(bindAddr: bindAddr.toString())
    }
    
    func stopProxy() {
        EmotionalDamage.stop()
    }
}
