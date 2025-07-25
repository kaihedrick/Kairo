// filepath: BibleAppPOCV2/VerseSummaryViewModel.swift
// filepath: BibleAppPOCV2/VerseSummaryViewModel.swift
import Foundation
import Combine

/// ViewModel to manage MLX verse summarization and UI state
class VerseSummaryViewModel: ObservableObject {
    @Published var summary: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    private let summarizer = MLXVerseSummarizer()
    
    func summarizeVerse(_ verse: String) {
        isLoading = true
        error = nil
        Task {
            let result = await summarizer.summarize(verse: verse)
            await MainActor.run {
                self.summary = result
                self.isLoading = false
            }
        }
    }
}
