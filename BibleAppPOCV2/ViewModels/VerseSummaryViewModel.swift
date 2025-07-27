// File: BibleAppPOCV2/ViewModels/VerseSummaryViewModel.swift
// Directory: ViewModels
// Purpose: Use BART model for real text generation and verse summarization

import Foundation

class VerseSummaryViewModel: ObservableObject {
    @Published var summaryText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    
    private let bartService = BARTService()

    // Accepts a verse string, runs through BART pipeline, and updates summaryText
    func summarize(verse: String) {
        isLoading = true
        errorMessage = ""
        
        // Run on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let summary = self?.bartService.generateSummary(for: verse) ?? "Error: Could not generate summary"
            
            DispatchQueue.main.async {
                self?.isLoading = false
                if summary.hasPrefix("Error:") {
                    self?.errorMessage = summary
                    self?.summaryText = "Failed to generate summary"
                } else {
                    self?.summaryText = summary
                }
            }
        }
    }
    
    // Clear the current summary
    func clearSummary() {
        summaryText = ""
        errorMessage = ""
    }
}
