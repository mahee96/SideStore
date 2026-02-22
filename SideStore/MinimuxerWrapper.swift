//
//  MinimuxerWrapper.swift
//  SideStore
//
//  Created by Jackson Coxson on 10/26/22.
//

import Foundation
import minimuxer

var isMinimuxerReady: Bool {
    #if targetEnvironment(simulator)
    print("isMinimuxerReady property is always true on simulator")
    return true
    #else
    return minimuxer.ready()
    #endif
}

func minimuxerStartWithLogger(_ pairingFile: String,_ logPath: String,_ loggingEnabled: Bool) throws {
    #if targetEnvironment(simulator)
    print("minimuxerStartWithLogger(\(pairingFile), \(logPath), \(loggingEnabled) is no-op on simulator")
    #else
    try minimuxer.startWithLogger(pairingFile, logPath, loggingEnabled)
    #endif
}

func targetMinimuxerAddress() {
    #if targetEnvironment(simulator)
    print("targetMinimuxerAddress() is no-op on simulator")
    #else
    minimuxer.target_minimuxer_address()
    #endif
}
