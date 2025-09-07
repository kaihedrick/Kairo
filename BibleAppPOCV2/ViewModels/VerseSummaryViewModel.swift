// filepath: BibleAppPOCV2/ViewModels/VerseSummaryViewModel.swift

import Foundation

@MainActor
class VerseSummaryViewModel: ObservableObject {
    static let shared = VerseSummaryViewModel()
    
    @Published var commentaryText: String = ""
    @Published var devotionalText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var modelVersion: String = "GPT-2 Bible Commentary Model"
    @Published var modelAvailable: Bool = false
    
    private var bibleCommentaryGenerator: BibleCommentaryGenerator?
    private var pendingVerse: String?
    private var initializationStartTime: Date?
    private var initializationGracePeriod: TimeInterval = 1.0 // 1 second grace period

    init() {
        initializationStartTime = Date()
        attachModelReadyObserver()
        // Get initial readiness state directly from BibleCommentaryGenerator
        modelAvailable = BibleCommentaryGenerator.shared.isReady
        Task { await initializeGenerators() }
    }
    
    @MainActor
    private func attachModelReadyObserver() {
        print("👂 VerseSummaryViewModel: Setting up BibleCommentaryGenerator notification observer")
        // Listen for BibleCommentaryGenerator readiness changes
        NotificationCenter.default.addObserver(
            forName: GenerationRuntime.runtimeModeChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let userInfo = notification.userInfo,
               let newMode = userInfo[GenerationRuntime.runtimeModeKey] as? InferenceMode {
                self.modelAvailable = (newMode == .coreml)
                print("🔄 VerseSummaryViewModel: Readiness changed to: \(newMode), modelAvailable: \(self.modelAvailable)")

                // Clear any loading errors when CoreML becomes ready
                if newMode == .coreml {
                    if self.errorMessage == "Core ML model is loading..." {
                        self.errorMessage = ""
                        print("✅ Cleared loading error - CoreML is now ready")
                    }

                    // Auto-retry pending verse when CoreML becomes ready
                    if let pendingVerse = self.pendingVerse {
                        print("🚀 Auto-retrying pending verse: \(pendingVerse.prefix(50))...")
                        self.pendingVerse = nil
                        self.summarize(verse: pendingVerse)
                    }
                }
            }
        }

        // Set initial state from BibleCommentaryGenerator
        modelAvailable = BibleCommentaryGenerator.shared.isReady
        print("👂 VerseSummaryViewModel: Initial readiness: \(modelAvailable)")
    }

    @MainActor
    private func initializeGenerators() async {
        // Initialize the GPT-2 Bible commentary generator
        bibleCommentaryGenerator = BibleCommentaryGenerator.shared
        print("✅ BibleCommentaryGenerator initialized successfully")
    }

    // Helper method to check if we're still within initialization grace period
    private func isWithinGracePeriod() -> Bool {
        guard let startTime = initializationStartTime else { return false }
        return Date().timeIntervalSince(startTime) < initializationGracePeriod
    }

    // Helper method to set error message with grace period consideration
    private func setErrorMessage(_ message: String) {
        if isWithinGracePeriod() {
            print("⏳ Deferring error during grace period: \(message)")
            // Don't show the error immediately, but set it after grace period
            // unless CoreML becomes ready first
            Task { @MainActor in
                let remainingTime = initializationGracePeriod - Date().timeIntervalSince(initializationStartTime!)
                if remainingTime > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
                }
                // Only set error if CoreML is still not ready and no other error is shown
                if errorMessage.isEmpty && !BibleCommentaryGenerator.shared.isReady {
                    errorMessage = message
                }
            }
        } else {
            errorMessage = message
        }
    }

    // Accepts a verse string, runs through GPT-2 commentary generator pipeline, and updates commentary and devotional
    func summarize(verse: String) {
        // Immediately set loading state to show loading indicator
        isLoading = true
        setErrorMessage("")
        guard let commentaryGenerator = bibleCommentaryGenerator else {
            // Store pending verse to retry when Core ML becomes ready
            pendingVerse = verse
            setErrorMessage("Core ML model is loading...")
            print("⚠️ Generator not ready yet, waiting for Core ML to load...")
            return
        }

        // Check if the Core ML model is ready before proceeding
        guard commentaryGenerator.isReady else {
            // Store pending verse to retry when Core ML becomes ready
            pendingVerse = verse
            setErrorMessage("Core ML model is loading...")
            print("⚠️ Core ML model not ready yet, waiting for initialization...")
            print("🔍 DEBUG: commentaryGenerator.isReady = \(commentaryGenerator.isReady)")
            print("🔍 DEBUG: commentaryGenerator.model = \(commentaryGenerator.model != nil ? "loaded" : "nil")")
            return
        }
        
        print("🚀 calling generateCommentary with modelAvailable=\(modelAvailable), textLen=\(verse.count)")
        print("🚀 run(): modelAvailable=\(modelAvailable), vm id:", ObjectIdentifier(self))
        isLoading = true
        setErrorMessage("")
        commentaryText = ""
        devotionalText = ""
        modelVersion = "GPT-2 Bible Commentary Model"
        
        // Run on background thread to avoid blocking UI
        Task {
            do {
                // Wait for generator to be ready (this prevents race conditions)
                var waitCount = 0
                while !commentaryGenerator.isReady && waitCount < 50 { // Max 5 seconds
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    waitCount += 1
                    print("⏳ Waiting for generator... attempt \(waitCount)/50")
                }

                if !commentaryGenerator.isReady {
                    print("❌ TIMEOUT: Generator never became ready after 5 seconds")
                    throw NSError(domain: "VerseSummaryViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core ML model failed to load within timeout"])
                }
                
                // Try GPT-2 commentary generator first
                // Parse the verse to extract reference and text properly
                let (verseRef, verseText) = parseVerse(verse)
                
                // Generate commentary using the actual API
                let rawText = await commentaryGenerator.generateCommentary(for: verseRef, verseText: verseText)

                // Parse the structured output to extract commentary and devotional sections
                let parsedContent = parseStructuredOutput(rawText, originalVerse: verse)

                print("🔍 DEBUG: Raw text from ML model: '\(rawText)'")
                print("🔍 DEBUG: Parsed commentary: '\(parsedContent.commentary)'")
                print("🔍 DEBUG: Parsed devotional: '\(parsedContent.devotional)'")
                print("🔍 DEBUG: Original verse: '\(verse)'")

            await MainActor.run {
                self.isLoading = false

                // Use the parsed sections directly
                self.commentaryText = parsedContent.commentary
                self.devotionalText = parsedContent.devotional
                
                if parsedContent.commentary.isEmpty && parsedContent.devotional.isEmpty {
                    print("🔍 DEBUG: Both commentary and devotional are empty")
                    // Only try fallback summarizer if we're in fallback mode
                    if !BibleCommentaryGenerator.shared.isReady {
                        self.tryFallbackSummarizer(verse: verse)
                    } else {
                        self.setErrorMessage("No content generated from Core ML model")
                    }
                } else if parsedContent.commentary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                         parsedContent.devotional.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("🔍 DEBUG: Commentary and devotional contain only whitespace")
                    self.setErrorMessage("Generated content is empty or only whitespace")
                } else {
                    print("🔍 DEBUG: Content generation successful!")
                    self.errorMessage = ""
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                // Use setErrorMessage to respect grace period
                self.setErrorMessage("Generation failed: \(error.localizedDescription)")
            }
        }
        }
    }
    
    // Fallback to improved summarizer if GPT-2 fails
    private func tryFallbackSummarizer(verse: String) {
        // Only use fallback summarizer when CoreML is not ready
        guard !BibleCommentaryGenerator.shared.isReady else {
            setErrorMessage("Fallback summarizer not available in Core ML mode")
            return
        }
        
        // Note: improvedSummarizer is not currently implemented
        // Fallback to simple static response for now
        commentaryText = "Fallback commentary not currently available. Please ensure Core ML model is loaded."
        devotionalText = "Fallback devotional not currently available. Please ensure Core ML model is loaded."
        setErrorMessage("Fallback summarizer not implemented")
        return
        

    }
    
    // Parse structured output to extract commentary and devotional sections
    private func parseStructuredOutput(_ text: String, originalVerse: String) -> (commentary: String, devotional: String) {
        func slice(_ s: String, _ a: String, _ b: String) -> String {
            guard let r1 = s.range(of: a), let r2 = s.range(of: b), r1.upperBound <= r2.lowerBound else { return "" }
            return String(s[r1.upperBound..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // First try to parse structured output with markers
        let commentary = slice(text, "[START_COMMENTARY]", "[END_COMMENTARY]")
        let devotional = slice(text, "[START_DEVOTIONAL]", "[END_DEVOTIONAL]")

        // If structured markers are found, return them
        if !commentary.isEmpty || !devotional.isEmpty {
            return (commentary, devotional)
        }

        // If no structured markers found, treat the entire generated text as commentary
        // Remove the original verse text from the beginning to get just the generated content
        if text.hasPrefix(originalVerse) && text.count > originalVerse.count {
            // Extract everything after the original verse
            let startIndex = text.index(text.startIndex, offsetBy: originalVerse.count)
            let generatedContent = String(text[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (generatedContent, "")
        }

        // Fallback: use the entire text as commentary
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }
    
    // Clear the current summary
    func clearSummary() {
        commentaryText = ""
        devotionalText = ""
        setErrorMessage("")
    }
    
    /// Parse a verse string to extract the reference and text
    /// Handles formats like "Matthew 1:1 In the beginning..." or "6 1 Take heed..."
    private func parseVerse(_ verse: String) -> (verseRef: String, verseText: String) {
        // First, try to find a verse reference pattern like "Book Chapter:Verse"
        let versePattern = #"^([A-Za-z]+)\s+(\d+):(\d+)\s+(.+)$"#
        
        if let regex = try? NSRegularExpression(pattern: versePattern, options: []),
           let match = regex.firstMatch(in: verse, options: [], range: NSRange(verse.startIndex..., in: verse)) {
            
            let book = String(verse[Range(match.range(at: 1), in: verse)!])
            let chapter = String(verse[Range(match.range(at: 2), in: verse)!])
            let verseNum = String(verse[Range(match.range(at: 3), in: verse)!])
            let text = String(verse[Range(match.range(at: 4), in: verse)!])
            
            let verseRef = "\(book) \(chapter):\(verseNum)"
            return (verseRef, text)
        }
        
        // If that doesn't work, try to find a pattern like "Chapter Verse Text"
        let chapterVersePattern = #"^(\d+)\s+(\d+)\s+(.+)$"#
        
        if let regex = try? NSRegularExpression(pattern: chapterVersePattern, options: []),
           let match = regex.firstMatch(in: verse, options: [], range: NSRange(verse.startIndex..., in: verse)) {
            
            let chapter = String(verse[Range(match.range(at: 1), in: verse)!])
            let verseNum = String(verse[Range(match.range(at: 2), in: verse)!])
            let text = String(verse[Range(match.range(at: 3), in: verse)!])
            
            // Try to infer the book from context or use a default
            let verseRef = "Chapter \(chapter):\(verseNum)"
            return (verseRef, text)
        }
        
        // If all else fails, use the simple approach but limit the verse reference
        let components = verse.components(separatedBy: " ")
        if components.count >= 3 {
            // Look for a pattern like "Book Chapter:Verse" or "Chapter Verse"
            let firstTwo = "\(components[0]) \(components[1])"
            
            // Check if the second component contains a colon (indicating verse reference)
            if components[1].contains(":") {
                let verseRef = firstTwo
                let verseText = components.dropFirst(2).joined(separator: " ")
                return (verseRef, verseText)
            } else if components.count >= 3 && components[2].contains(":") {
                // Pattern like "Book Chapter Verse:Number"
                let verseRef = "\(components[0]) \(components[1]):\(components[2].split(separator: ":")[1])"
                let verseText = components.dropFirst(3).joined(separator: " ")
                return (verseRef, verseText)
            } else {
                // Simple case: take first two words as reference
                let verseRef = firstTwo
                let verseText = components.dropFirst(2).joined(separator: " ")
                return (verseRef, verseText)
            }
        }
        
        // Fallback: return the whole string as text
        return ("Unknown", verse)
    }
    
    // Get the status of the generators
    func getSummarizerStatus() -> String {
        if let commentaryGenerator = bibleCommentaryGenerator, commentaryGenerator.isReady {
            return "GPT-2 Bible Commentary Model Ready"
        } else if bibleCommentaryGenerator != nil {
            return "GPT-2 Bible Commentary Model Loading..."
        } else if !BibleCommentaryGenerator.shared.isReady {
            return "Fallback Mode (Improved Bible AI Model Not Implemented)"
        } else {
            return "No models available"
        }
    }
    
    // Check if the generators are ready
    func isSummarizerReady() -> Bool {
        if let commentaryGenerator = bibleCommentaryGenerator {
            return commentaryGenerator.isReady
        }
        return false  // Only BibleCommentaryGenerator is implemented
    }
    
    // Get detailed status information for debugging
    func getDetailedStatus() -> String {
        var status = "BibleCommentaryGenerator Ready: \(BibleCommentaryGenerator.shared.isReady)\n"
        status += "Model Available: \(modelAvailable)\n"
        
        if let commentaryGenerator = bibleCommentaryGenerator {
            status += "BibleCommentaryGenerator: \(commentaryGenerator.isReady ? "Ready" : "Loading")\n"
        } else {
            status += "BibleCommentaryGenerator: Not Initialized\n"
        }
        
        status += "ImprovedBibleSummarizer: Not Implemented\n"
        
        return status
    }
    
    // Retry initialization
    func retryInitialization() {
        setErrorMessage("")
        Task { await initializeGenerators() }
    }
}
