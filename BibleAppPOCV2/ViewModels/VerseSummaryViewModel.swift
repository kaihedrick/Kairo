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
        // Initial readiness state from BibleCommentaryGenerator
        modelAvailable = BibleCommentaryGenerator.shared.isReady
        Task { await initializeGenerators() }
    }

    // MARK: - Observers & Initialization
    @MainActor
    private func attachModelReadyObserver() {
        print("👂 VerseSummaryViewModel: Setting up GenerationRuntime notification observer")
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

                if newMode == .coreml {
                    if self.errorMessage == "Core ML model is loading..." {
                        self.errorMessage = ""
                        print("✅ Cleared loading error - CoreML is now ready")
                    }

                    // Auto-retry pending verse
                    if let pendingVerse = self.pendingVerse {
                        print("🚀 Auto-retrying pending verse: \(pendingVerse.prefix(50))...")
                        self.pendingVerse = nil
                        self.summarize(verse: pendingVerse)
                    }
                }
            }
        }

        modelAvailable = BibleCommentaryGenerator.shared.isReady
        print("👂 VerseSummaryViewModel: Initial readiness: \(modelAvailable)")
    }

    @MainActor
    private func initializeGenerators() async {
        bibleCommentaryGenerator = BibleCommentaryGenerator.shared
        print("✅ BibleCommentaryGenerator initialized successfully")
    }

    // MARK: - Error Handling
    private func isWithinGracePeriod() -> Bool {
        guard let startTime = initializationStartTime else { return false }
        return Date().timeIntervalSince(startTime) < initializationGracePeriod
    }

    private func setErrorMessage(_ message: String) {
        if isWithinGracePeriod() {
            print("⏳ Deferring error during grace period: \(message)")
            Task { @MainActor in
                let remainingTime = initializationGracePeriod - Date().timeIntervalSince(initializationStartTime!)
                if remainingTime > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
                }
                if errorMessage.isEmpty && !BibleCommentaryGenerator.shared.isReady {
                    errorMessage = message
                }
            }
        } else {
            errorMessage = message
        }
    }

    // MARK: - Summarization
    func summarize(verse: String) {
        isLoading = true
        setErrorMessage("")
        
        guard let commentaryGenerator = bibleCommentaryGenerator else {
            pendingVerse = verse
            setErrorMessage("Core ML model is loading...")
            print("⚠️ Generator not ready yet, waiting for Core ML to load...")
            return
        }

        guard commentaryGenerator.isReady else {
            pendingVerse = verse
            setErrorMessage("Core ML model is loading...")
            print("⚠️ Core ML model not ready yet")
            return
        }
        
        print("🚀 Running generateCommentaryFromDatabaseOnly for verse: \(verse)")
        commentaryText = ""
        devotionalText = ""
        modelVersion = "Enhanced Bible Database (Database Only - No AI)"

        Task {
            do {
                var waitCount = 0
                while !commentaryGenerator.isReady && waitCount < 50 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    waitCount += 1
                    print("⏳ Waiting for generator... attempt \(waitCount)/50")
                }

                if !commentaryGenerator.isReady {
                    throw NSError(domain: "VerseSummaryViewModel", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Core ML model failed to load within timeout"])
                }
                
                // Use database-only generation (no parsing needed)
                if let rawText = await commentaryGenerator.generateCommentaryFromDatabaseOnly(for: verse) {
                    let parsedContent = parseStructuredOutput(rawText, originalVerse: verse)

                    await MainActor.run {
                        self.isLoading = false
                        self.commentaryText = parsedContent.commentary
                        self.devotionalText = parsedContent.devotional

                        if parsedContent.commentary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                            parsedContent.devotional.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.setErrorMessage("No commentary content available for this verse")
                        } else {
                            self.errorMessage = ""
                        }
                    }
                } else {
                    // No content found in database
                    await MainActor.run {
                        self.isLoading = false
                        self.commentaryText = "No commentary available"
                        self.devotionalText = "No devotional content available for this verse."
                        self.setErrorMessage("Verse content not found in database")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.setErrorMessage("Generation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func tryFallbackSummarizer(verse: String) {
        guard !BibleCommentaryGenerator.shared.isReady else {
            setErrorMessage("Fallback summarizer not available in Core ML mode")
            return
        }
        commentaryText = "Fallback commentary not available."
        devotionalText = "Fallback devotional not available."
        setErrorMessage("Fallback summarizer not implemented")
    }

    // MARK: - Parsing
    private func parseStructuredOutput(_ text: String, originalVerse: String) -> (commentary: String, devotional: String) {
        // Split on double newline to separate commentary from devotional
        let components = text.components(separatedBy: "\n\n")

        if components.count >= 2 {
            let commentary = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let devotional = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return (commentary, devotional)
        } else if components.count == 1 {
            // Only commentary was generated
            let commentary = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            return (commentary, "")
        }

        // Fallback: return entire text as commentary
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    // MARK: - Utilities
    func clearSummary() {
        commentaryText = ""
        devotionalText = ""
        setErrorMessage("")
    }


    func getSummarizerStatus() -> String {
        if let gen = bibleCommentaryGenerator, gen.isReady {
            return "Enhanced Bible Database Ready (Database Only - No AI)"
        } else if bibleCommentaryGenerator != nil {
            return "Enhanced Bible Database Loading..."
        } else if !BibleCommentaryGenerator.shared.isReady {
            return "Database Not Available"
        }
        return "No database systems available"
    }

    func isSummarizerReady() -> Bool {
        return bibleCommentaryGenerator?.isReady ?? false
    }

    func getDetailedStatus() -> String {
        var status = "Enhanced Bible Database Ready: \(BibleCommentaryGenerator.shared.isReady)\n"
        status += "AI/ML Generation: Disabled\n"
        if let gen = bibleCommentaryGenerator {
            status += "BibleCommentaryGenerator: \(gen.isReady ? "Ready" : "Loading")\n"
        } else {
            status += "BibleCommentaryGenerator: Not Initialized\n"
        }
        status += "Generation Strategy: Database-only (No AI/ML)\n"
        return status
    }

    func retryInitialization() {
        setErrorMessage("")
        Task { await initializeGenerators() }
    }
}
