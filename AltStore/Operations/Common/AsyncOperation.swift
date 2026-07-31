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
    func execute(parentProgress: Progress?) async throws -> T
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
    
    func setProgress(_ completedUnitCount: Int64) {
        let previous = self.progress.completedUnitCount
        self.progress.completedUnitCount = completedUnitCount
        verboseLog("[\(String(describing: type(of: self)))] Progress updated: \(previous) -> \(completedUnitCount) (total: \(self.progress.totalUnitCount))")
    }
    
    func executePreconditionCheck(parentProgress: Progress?) async throws {
        let className = String(describing: type(of: self))
        debugLog("[\(className)] executePreconditionCheck() started")
        defer { debugLog("[\(className)] executePreconditionCheck() completed") }
        
        let unitCount: Int64
        if let parentProgress = parentProgress {
            let steps = self.context.steps.isEmpty ? [ExecutionStep(self.stepType, 100)] : self.context.steps
            if let match = steps.first(where: { $0.step == self.stepType }) {
                unitCount = match.weight
            } else {
                throw OperationError.invalidParameters("Missing progress weight for operation step: \(self.stepType) in steps list")
            }
            
            if unitCount > 0 {
                verboseLog("[\(className)] Adding child progress to parent with weight: \(unitCount) (parent total: \(parentProgress.totalUnitCount))")
                parentProgress.addChild(self.progress, withPendingUnitCount: unitCount)
            }
        }
        if self.isCancelled {
            throw OperationError.cancelled
        }
        if let error = self.context.error {
            throw error
        }
    }
    
    @discardableResult
    func execute(parentProgress: Progress?) async throws -> Result
    {
        throw AbstractClassError.abstractMethodInvoked
    }
    
    @discardableResult
    func execute() async throws -> Result {
        try await self.execute(parentProgress: nil)
    }
    
    func cancel() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.isCancelled = true
    }
}
