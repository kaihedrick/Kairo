// filepath: BibleAppPOCV2/ViewModels/OptimizedBibleViewModel.swift
//
//  OptimizedBibleViewModel.swift
//  AIStudyBiblePOC
//
//  Created by Performance Optimization on 6/13/25.
//

import Foundation
import SwiftUI

// MARK: - Optimized Bible View Model

@MainActor
class OptimizedBibleViewModel: ObservableObject {
    // Use the improved models explicitly to avoid type ambiguity
    @Published var metadata: ImprovedBibleModels.BibleMetadata?
    @Published var isInitializing = true
    @Published var initializationProgress: Double = 0.0
    @Published var errorMessage: String?
    
    // Support for dependency injection (for future translation support)
    private let repository: BibleRepositoryProtocol?
    private let dataLoader = OptimizedBibleDataLoader.shared
    
    init(repository: BibleRepositoryProtocol? = nil) {
        self.repository = repository
        Task {
            await initializeData()
        }
    }
    
    private func initializeData() async {
        do {
            // Start with metadata loading
            initializationProgress = 0.1
            
            // Use repository if available (for translation support), otherwise fallback to direct loader
            if let repository = repository {
                let loadedMetadata = try await repository.loadMetadata()
                metadata = loadedMetadata
            } else {
                try await dataLoader.loadBibleMetadata()
                metadata = await dataLoader.metadata
            }
            
            initializationProgress = 0.8
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
    func initializeDataImproved() async {
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
    func searchBooksImproved(query: String) async -> [ImprovedBibleModels.BookMetadata] {
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