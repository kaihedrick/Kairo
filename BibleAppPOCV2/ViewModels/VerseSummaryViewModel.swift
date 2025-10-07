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
        #if AI_FEATURES
        attachModelReadyObserver()
        #endif
        attachVerseTapObserver()
        // DB-only mode: ready immediately, no generator warmup
        modelAvailable = true
    }

    // MARK: - Observers & Initialization
    @MainActor
    private func attachVerseTapObserver() {
        #if DEBUG
        if VerboseLogs.viewModel {
            print("👂 VerseSummaryViewModel: Setting up verse tap notification observer")
        }
        #endif

        // Import the notification name
        let notificationName = NSNotification.Name("kairoVerseTapped")

        NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            guard let payload = notification.userInfo?["payload"] as? VerseTapPayload else {
                #if DEBUG
                assertionFailure("Missing VerseTapPayload in notification - this should never happen")
                if VerboseLogs.viewModel {
                    print("❌ CRITICAL: Missing VerseTapPayload in notification")
                    print("   Available keys: \(notification.userInfo?.keys.map { "\($0)" }.joined(separator: ", ") ?? "none")")
                }
                #endif
                return
            }

            #if DEBUG
            if VerboseLogs.viewModel {
                print("📨 RECEIVED VERSE TAP PAYLOAD: \(payload.description)")
                print("   Book: \(payload.book), Chapter: \(payload.chapter), Verse: \(payload.verse)")
            }
            #endif

            // Use the payload as the SINGLE source of truth
            Task {
                await self.summarize(book: payload.book, chapter: payload.chapter, verse: payload.verse)
            }
        }
    }

    @MainActor
    func summarize(book: String, chapter: Int, verse: Int) {
        Task {
            await self.summarize(book: book, chapter: chapter, verse: verse)
        }
    }

    // MARK: - Summarization
    @MainActor
    private func summarize(book: String, chapter: Int, verse: Int) async {
        let verseString = "\(book) \(chapter):\(verse)"
        await summarize(verse: verseString)
    }

    /// Legacy method for backward compatibility
    func summarize(verse: String) async {
        isLoading = true
        setErrorMessage("")

        // Lazy load generator - no eager initialization
        let generator = bibleCommentaryGenerator ?? BibleCommentaryGenerator.shared
        self.bibleCommentaryGenerator = generator

        #if DEBUG
        if VerboseLogs.viewModel {
            print("🚀 Running generateCommentaryFromDatabaseOnly for verse: \(verse)")
        }
        #endif
        
        commentaryText = ""
        devotionalText = ""
        modelVersion = "Enhanced Bible Database (Database Only - No AI)"

        // Use database-only generation (no ML readiness checks)
        if let rawText = await generator.generateCommentaryFromDatabaseOnly(for: verse) {
            let parsedContent = parseStructuredOutput(rawText, originalVerse: verse)

            await MainActor.run {
                self.isLoading = false
                self.commentaryText = parsedContent.commentary
                self.devotionalText = parsedContent.devotional

                if parsedContent.commentary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    parsedContent.devotional.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.setErrorMessage("No commentary content available for this verse")
                }
                #if DEBUG
                else if VerboseLogs.viewModel {
                    print("✅ Successfully loaded commentary and devotional content")
                }
                #endif
            }
        } else {
            await MainActor.run {
                self.isLoading = false
                self.commentaryText = "No commentary available"
                self.devotionalText = "No devotional content available for this verse."
                self.setErrorMessage("Verse content not found in database")
            }
        }
    }

    @MainActor
    private func attachModelReadyObserver() {
        #if DEBUG
        if VerboseLogs.viewModel {
            print("👂 VerseSummaryViewModel: Setting up GenerationRuntime notification observer")
        }
        #endif
        
        NotificationCenter.default.addObserver(
            forName: GenerationRuntime.runtimeModeChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let userInfo = notification.userInfo,
               let newMode = userInfo[GenerationRuntime.runtimeModeKey] as? InferenceMode {
                self.modelAvailable = (newMode == .coreml)
                
                #if DEBUG
                if VerboseLogs.viewModel {
                    print("🔄 VerseSummaryViewModel: Readiness changed to: \(newMode), modelAvailable: \(self.modelAvailable)")
                }
                #endif

                if newMode == .coreml {
                    if self.errorMessage == "Core ML model is loading..." {
                        self.errorMessage = ""
                        #if DEBUG
                        if VerboseLogs.viewModel {
                            print("✅ Cleared loading error - CoreML is now ready")
                        }
                        #endif
                    }

                    // Auto-retry pending verse
                    if let pendingVerse = self.pendingVerse {
                        #if DEBUG
                        if VerboseLogs.viewModel {
                            print("🚀 Auto-retrying pending verse: \(pendingVerse.prefix(50))...")
                        }
                        #endif
                        self.pendingVerse = nil
                        Task {
                            await self.summarize(verse: pendingVerse)
                        }
                    }
                }
            }
        }

        // DB-only mode: always ready
        modelAvailable = true
        
        #if DEBUG
        if VerboseLogs.viewModel {
            print("👂 VerseSummaryViewModel: Initial readiness: \(modelAvailable)")
        }
        #endif
    }

    @MainActor
    private func initializeGenerators() async {
        // DB-only mode - no initialization needed
        #if DEBUG
        if VerboseLogs.viewModel {
            print("✅ DB-only mode: no generator initialization needed")
        }
        #endif
    }

    // MARK: - Error Handling
    private func isWithinGracePeriod() -> Bool {
        guard let startTime = initializationStartTime else { return false }
        return Date().timeIntervalSince(startTime) < initializationGracePeriod
    }

    private func setErrorMessage(_ message: String) {
        if isWithinGracePeriod() {
            #if DEBUG
            if VerboseLogs.viewModel {
                print("⏳ Deferring error during grace period: \(message)")
            }
            #endif
            Task { @MainActor in
                let remainingTime = initializationGracePeriod - Date().timeIntervalSince(initializationStartTime!)
                if remainingTime > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
                }
                if errorMessage.isEmpty {
                    errorMessage = message
                }
            }
        } else {
            errorMessage = message
        }
    }

    // MARK: - Summarization
    /// Legacy method for backward compatibility (public interface)
    func summarize(verse: String) {
        Task {
            await self.summarize(verse: verse)
        }
    }

    private func tryFallbackSummarizer(verse: String) {
        // DB-only mode - no fallback needed
        commentaryText = "No commentary available"
        devotionalText = "No devotional content available for this verse."
        setErrorMessage("Verse content not found in database")
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
        return "Enhanced Bible Database Ready (Database Only - No AI)"
    }

    func isSummarizerReady() -> Bool {
        return true // DB-only mode is always ready
    }

    func getDetailedStatus() -> String {
        var status = "Enhanced Bible Database Ready: true\n"
        status += "AI/ML Generation: Disabled\n"
        status += "BibleCommentaryGenerator: DB-Only Mode\n"
        status += "Generation Strategy: Database-only (No AI/ML)\n"
        return status
    }

    func retryInitialization() {
        setErrorMessage("")
        // DB-only mode - no initialization needed
        #if DEBUG
        if VerboseLogs.viewModel {
            print("✅ DB-only mode: retry not needed")
        }
        #endif
    }
}
