//
//  AsyncOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
@preconcurrency import AltStoreCore

class AsyncOperation<Context: OperationContext, Result>: NSObject, ProgressReporting, OperationLogging, @unchecked Sendable {
    private(set) var progress: Progress!
    private(set) var context: Context!
    
    private(set) var isCancelled = false
    private let lock = NSLock()
    
    var stepType: OperationStep {
        OperationStep.step(for: type(of: self))
    }
    
    var totalUnitCount: Int64 { 100 }
    
    init(context: Context) {
        super.init()
        self.context = context
        self.progress = Progress.discreteProgress(totalUnitCount: self.totalUnitCount)
        self.progress.cancellationHandler = { [weak self] in self?.cancel() }
    }
    
    @discardableResult
    func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> Result {
        let unitCount = weights?[self.stepType] ?? pendingUnitCount
        if let parentProgress = parentProgress, unitCount > 0 {
            parentProgress.addChild(self.progress, withPendingUnitCount: unitCount)
        }
        if self.isCancelled {
            throw OperationError.cancelled
        }
        if let error = self.context.error {
            throw error
        }
        throw AbstractClassError.abstractMethodInvoked
    }
    
    @discardableResult
    func execute(parentProgress: Progress?, weights: [OperationStep: Int64]?) async throws -> Result {
        try await self.execute(parentProgress: parentProgress, pendingUnitCount: 0, weights: weights)
    }
    
    @discardableResult
    func execute(parentProgress: Progress? = nil, pendingUnitCount: Int64 = 1) async throws -> Result {
        try await self.execute(parentProgress: parentProgress, pendingUnitCount: pendingUnitCount, weights: nil)
    }
    
    func cancel() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.isCancelled = true
    }
}
