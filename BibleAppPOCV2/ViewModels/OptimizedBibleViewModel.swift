//
//  OptimizedBibleViewModel.swift
//  AIStudyBiblePOC
//
//  Created by Performance Optimization on 6/13/25.
//

import Foundation
import SwiftUI

// MARK: - Performance Monitor Integration

// Use the shared PerformanceMonitor from Utilities folder

// MARK: - Optimized Bible View Model

@MainActor
class OptimizedBibleViewModel: ObservableObject {
    @Published var metadata: BibleMetadata?
    @Published var isInitializing = true
    @Published var initializationProgress: Double = 0.0
    @Published var errorMessage: String?
    
    private let dataLoader = OptimizedBibleDataLoader()
    
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