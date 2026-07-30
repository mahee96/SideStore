//
//  AsyncOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
@preconcurrency import AltStoreCore

protocol AsyncOperation<T>: AnyObject, ProgressReporting, OperationLogging {
    associatedtype T
    
    var isCancelled: Bool { get }
    var stepType: OperationStep { get }

    @discardableResult
    func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> T
    func cancel()
}

class BaseOperation<Context: OperationContext, Result>: NSObject, AsyncOperation, @unchecked Sendable{
    typealias T = Result

    private(set) var _progress: Progress!
    private(set) var progress: Progress {
        get { _progress }
        set { _progress = newValue }
    }
    private(set) var context: Context!
    
    private(set) var isCancelled = false
    private let lock = NSLock()
    
    var stepType: OperationStep {
        OperationStep.step(for: type(of: self))
    }
    
    var totalUnitCount: Int64 { 100 }
    
    init(context: Context) throws {
        if Self.self === BaseOperation.self {
            throw AbstractClassError.abstractInitializerInvoked
        }
        super.init()        
        self.context = context
        self.progress = Progress.discreteProgress(totalUnitCount: self.totalUnitCount)
        self.progress.cancellationHandler = { [weak self] in self?.cancel() }
    }
    
    func executePreconditionCheck(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws {
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
    }
    
    @discardableResult
    func execute(parentProgress: Progress?, pendingUnitCount: Int64, weights: [OperationStep: Int64]?) async throws -> Result
    {
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
