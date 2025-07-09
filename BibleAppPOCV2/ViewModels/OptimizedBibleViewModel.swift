//
//  OptimizedBibleViewModel.swift
//  AIStudyBiblePOC
//
//  Created by Performance Optimization on 6/13/25.
//

import Foundation
import SwiftUI

// MARK: - Performance Monitor

@MainActor
class PerformanceMonitor: ObservableObject {
    @Published var memoryUsage: String = "0 MB"
    @Published var cacheHitRate: Double = 0.0
    
    private var totalRequests: Int = 0
    private var cacheHits: Int = 0
    
    init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateMemoryUsage()
            }
        }
    }
    
    private func updateMemoryUsage() {
        var taskInfo = mach_task_basic_info()  // Use 'var' instead of 'let'
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) { ptr in
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         ptr,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let memoryInMB = Double(taskInfo.resident_size) / 1024.0 / 1024.0
            memoryUsage = String(format: "%.1f MB", memoryInMB)
        }
    }
    
    func recordCacheHit() {
        totalRequests += 1
        cacheHits += 1
        updateCacheHitRate()
    }
    
    func recordCacheMiss() {
        totalRequests += 1
        updateCacheHitRate()
    }
    
    private func updateCacheHitRate() {
        guard totalRequests > 0 else { return }
        cacheHitRate = Double(cacheHits) / Double(totalRequests)
    }
}

// MARK: - Optimized Bible View Model

@MainActor
class OptimizedBibleViewModel: ObservableObject {
    @Published var metadata: BibleMetadata?
    @Published var isInitializing = true
    @Published var initializationProgress: Double = 0.0
    @Published var errorMessage: String?
    
    private let dataLoader = OptimizedBibleDataLoader.shared
    
    init() {
        Task {
            await initializeData()
        }
    }
    
    private func initializeData() async {
        do {
            // Start with metadata loading
            initializationProgress = 0.1
            
            try await dataLoader.loadBibleMetadata()
            initializationProgress = 0.8
            
            // Get metadata
            metadata = await dataLoader.metadata
            initializationProgress = 1.0
            
            // Small delay to show completion
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            isInitializing = false
            
        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
            isInitializing = false
        }
    }
    
    // MARK: - Improved Architecture Methods

    /// Improved initialization with better error handling
    private func initializeDataImproved() async {
        do {
            // Start with metadata loading
            initializationProgress = 0.1
            
            // Use dependency injection pattern (preparation for future migration)
            let dataLoader = OptimizedBibleDataLoader.shared
            
            try await dataLoader.loadBibleMetadata()
            initializationProgress = 0.8
            
            // Get metadata with better error handling
            guard let loadedMetadata = await dataLoader.metadata else {
                throw ImprovedBibleError.dataNotFound("Bible metadata")
            }
            
            metadata = loadedMetadata
            initializationProgress = 1.0
            
            // Small delay to show completion
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            isInitializing = false
            
        } catch {
            handleError(error)
            isInitializing = false
        }
    }

    /// Improved error handling
    private func handleError(_ error: Error) {
        if let bibleError = error as? ImprovedBibleError {
            errorMessage = bibleError.localizedDescription
        } else {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    /// Search books with improved architecture
    func searchBooksImproved(query: String) async -> [BookMetadata] {
        guard let metadata = metadata else { return [] }
        
        // Use better filtering with validation
        return metadata.books.filter { book in
            !book.name.isEmpty && 
            book.name.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Improved Error Types

    enum ImprovedBibleError: LocalizedError {
        case dataNotFound(String)
        case parsingError(String)
        case invalidInput(String)
        
        var errorDescription: String? {
            switch self {
            case .dataNotFound(let item):
                return "Could not find \(item)"
            case .parsingError(let detail):
                return "Parsing failed: \(detail)"
            case .invalidInput(let detail):
                return "Invalid input: \(detail)"
            }
        }
    }

    func handleMemoryWarning() {
        Task {
            await dataLoader.handleMemoryWarning()
        }
    }
    
    func retryInitialization() {
        errorMessage = nil
        isInitializing = true
        initializationProgress = 0.0
        
        Task {
            await initializeData()
        }
    }
}