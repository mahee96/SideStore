//
//  TaskChainCoalescer.swift
//  AltStore
//
//  Created by Magesh K on 31/7/26.
//

import Foundation

/*
 A coalescing actor that folds duplicate concurrent requests into a single task execution.
 All concurrent requests awaiting the same key will block on the same task, and receive 
 the identical result simultaneously.
 */
actor TaskChainCoalescer {
    static let shared = TaskChainCoalescer()
    
    private var activeTasks = [String: Task<Any, Error>]()
    
    func coalesce<T: Sendable>(key: String, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        if let existingTask = activeTasks[key] {
            let result = try await existingTask.value
            return result as! T
        }
        
        let newTask = Task<Any, Error> {
            let result = try await operation()
            return result
        }
        
        activeTasks[key] = newTask
        
        defer {
            Task {
                await self.removeTask(key: key)
            }
        }
        
        let result = try await newTask.value
        return result as! T
    }
    
    private func removeTask(key: String) {
        activeTasks.removeValue(forKey: key)
    }
}
