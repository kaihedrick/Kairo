import Foundation
import CoreML

// MARK: - Constants
private let EOS_TOKEN_ID: Int32 = 50256

// MARK: - Main BibleCommentaryGenerator Class
public final class BibleCommentaryGenerator {
    // MARK: - Engine Types
    public enum Engine {
        case dbOnly  // 🔒 Always use this
        // case ml     // Removed - AI disabled
    }

    private let engine: Engine = .dbOnly  // 🔒 Hard lock to DB-only
    // Properties needed by the bridge
    public var model: MLModel?
    public var endDevotionalId: Int32?
    public var padId: Int32?
    public var tokenizer: GPT2BPETokenizer?

    // Special token IDs for Python-exact prompt building
    public var verseIdId: Int32?
    public var verseRefId: Int32?
    public var verseTextId: Int32?
    public var verseId: Int32?
    public var startCommentaryId: Int32?

    // Shared instance for testing
    public static let shared = BibleCommentaryGenerator()

    // Ready state for testing
    public var isReady: Bool = false

    // Enhanced Bible Database for lookup-based generation
    private var enhancedDatabase: EnhancedBibleDatabase?
    

    /// Public accessor for the EnhancedBibleDatabase instance
    public var database: EnhancedBibleDatabase? {
        return enhancedDatabase
    }

    // Toggle for Python-exact prompt format
    public var usePythonExactPrompt: Bool = true

    /// Convenience method to toggle between prompt formats for A/B testing
    public func togglePromptFormat() {
        usePythonExactPrompt.toggle()
        print("🔄 Prompt format toggled to: \(usePythonExactPrompt ? "Python-exact" : "String-based")")
    }

    /// Get current prompt format description
    public var currentPromptFormat: String {
        usePythonExactPrompt ? "Python-exact (token-by-token)" : "String-based (compact)"
    }

    /// ✅ Specials can emit: test function with temp=1.0, no penalties
    public func testSpecialsEmission(ref: String, verseText: String) async throws -> String {
        guard let model = self.model, let tokenizer = self.tokenizer else {
            throw NSError(domain: "BibleCommentaryGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model or tokenizer not initialized"])
        }
        guard let endDevotionalId = self.endDevotionalId else {
            throw NSError(domain: "BibleCommentaryGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "END_DEVOTIONAL token not found"])
        }

        print("🧪 Testing specials emission with temp=1.0, no penalties...")

        // AI functionality is disabled - skip ML testing
        return "AI functionality disabled - using database-only generation"
    }

    /// ✅ Tokenizer round-trip test (check if Swift matches Python)
    public func testTokenizerRoundTrip() {
        guard let tokenizer = self.tokenizer else {
            print("❌ Tokenizer not initialized")
            return
        }

        let testString = "[VERSE_ID]Matthew1:3"
        let ids = tokenizer.encode(testString)
        let decoded = tokenizer.decode(ids)

        print("🔍 Tokenizer Round-Trip Test:")
        print("  Original: '\(testString)'")
        print("  Token IDs: \(ids)")
        print("  Decoded: '\(decoded)'")
        print("  Round-trip success: \(testString == decoded ? "✅ YES" : "❌ NO")")

        if testString != decoded {
            print("  ⚠️  MISMATCH! This could cause generation issues.")
            print("  Expected: \(testString.count) chars")
            print("  Got: \(decoded.count) chars")
        }
    }

    /// ✅ Special tokens verification (ensure all required markers are loaded)
    public func verifySpecialTokens() {
        print("🔍 Special Tokens Verification:")
        print("  VERSE_ID: \(verseIdId ?? -1)")
        print("  VERSE_REF: \(verseRefId ?? -1)")
        print("  VERSE_TEXT: \(verseTextId ?? -1)")
        print("  VERSE: \(verseId ?? -1)")
        print("  START_COMMENTARY: \(startCommentaryId ?? -1)")
        print("  END_DEVOTIONAL: \(endDevotionalId ?? -1)")
        print("  PAD: \(padId ?? -1)")

        let allPresent = verseIdId != nil && verseRefId != nil && verseTextId != nil &&
                        verseId != nil && startCommentaryId != nil && endDevotionalId != nil

        print("  All required specials loaded: \(allPresent ? "✅ YES" : "❌ NO")")

        if !allPresent {
            print("  ⚠️  Missing special tokens could cause generation issues!")
        }
    }

    /// ✅ Test parity with Python (create test input that matches Python script)
    public func testPythonParity(verseRef: String, verseText: String) async throws -> String {
        // 🚫 AI/ML functionality is disabled - return DB result only
        if FeatureGate.aiAvailable {
            print("🔬 Testing Python Parity:")
            print("  Input: '\(verseRef)' | '\(verseText.prefix(50))...'")

            // Create the exact same input format as Python script
            let norm = normalizeVerseId(verseRef)
            let pythonInputText = "[VERSE_ID]\(norm)[VERSE_REF]\(verseRef)[VERSE_TEXT]\(verseText)[VERSE][START_COMMENTARY]"

            print("  Python-format input: '\(pythonInputText)'")

            // Test encoding
            if let tokenizer = self.tokenizer {
                let pythonIds = tokenizer.encode(pythonInputText)
                print("  Encoded to \(pythonIds.count) tokens: \(pythonIds.prefix(10))...")
                print("  Decoded back: '\(tokenizer.decode(pythonIds))'")
            }
        } else {
            Log.info("🤖 AI disabled — skipping Python parity test")
        }

        // Always generate with our DB-only implementation
        return await generateCommentary(for: verseRef, verseText: verseText)
    }

    /// ✅ Performance measurement - measure generation time
    public func measureGenerationTime(verseRef: String, verseText: String) async throws -> (commentary: String, devotional: String, timeMs: Double) {
        // 🚫 AI/ML functionality is disabled - measure DB lookup time only

        // Measure DB lookup time
        let startTime = Date()
        let result = await generateCommentaryFromDatabaseOnly(for: verseRef)
        let endTime = Date()
        let timeMs = endTime.timeIntervalSince(startTime) * 1000

        // For DB-only, we don't have separate commentary/devotional sections
        // Return the full result as commentary and empty devotional
        return (commentary: result ?? "No commentary found", devotional: "", timeMs: timeMs)
    }

    /// ✅ Performance comparison - greedy vs sampling
    public func compareSamplingMethods(verseRef: String, verseText: String) async throws -> (greedy: (commentary: String, devotional: String, timeMs: Double), sampling: (commentary: String, devotional: String, timeMs: Double)) {
        // 🚫 AI/ML functionality is disabled - return DB result for both

        // For DB-only, both "greedy" and "sampling" return the same DB result
        let startTime = Date()
        let result = await generateCommentaryFromDatabaseOnly(for: verseRef)
        let endTime = Date()
        let timeMs = endTime.timeIntervalSince(startTime) * 1000

        let dbResult = (commentary: result ?? "No commentary found", devotional: "", timeMs: timeMs)
        return (greedy: dbResult, sampling: dbResult)
    }

    public init() {
        // 🚫 AI/ML initialization is completely disabled
        if FeatureGate.aiAvailable {
            print("🤖 AI features enabled - initializing tokenizer and model...")

            // Initialize the tokenizer from assets
            do {
                let artifacts = try TokenizerArtifacts.load()
                self.tokenizer = GPT2BPETokenizer(
                    vocab: artifacts.tokenToId,
                    merges: artifacts.merges,
                    idToToken: artifacts.idToToken
                )

                // Set special token IDs from added tokens
                self.endDevotionalId = artifacts.addedTokens["[END_DEVOTIONAL]"].map { Int32($0) }
                self.padId = artifacts.addedTokens["[PAD]"].map { Int32($0) }
                self.verseIdId = artifacts.addedTokens["[VERSE_ID]"].map { Int32($0) }
                self.verseRefId = artifacts.addedTokens["[VERSE_REF]"].map { Int32($0) }
                self.verseTextId = artifacts.addedTokens["[VERSE_TEXT]"].map { Int32($0) }
                self.verseId = artifacts.addedTokens["[VERSE]"].map { Int32($0) }
                self.startCommentaryId = artifacts.addedTokens["[START_COMMENTARY]"].map { Int32($0) }

                Log.ml("✅ Tokenizer initialized successfully")
                Log.ml("  - Vocab size: \(artifacts.tokenToId.count)")
                Log.ml("  - Added tokens: \(artifacts.addedTokens.count)")

            } catch {
                print("❌ Failed to initialize tokenizer: \(error.localizedDescription)")
                self.tokenizer = nil
            }

            // Initialize ML model if available
            do {
                let modelURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc")
                if let modelURL = modelURL {
                    let config = MLModelConfiguration()
                    self.model = try MLModel(contentsOf: modelURL, configuration: config)
                    Log.ml("✅ ML Model initialized successfully")
                } else {
                    Log.ml("⚠️ ML Model not found in bundle")
                    self.model = nil
                }
            } catch {
                Log.ml("❌ Failed to initialize ML model: \(error.localizedDescription)")
                self.model = nil
            }

        } else {
            // 🚫 AI is disabled - skip all ML/tokenizer initialization
            print("🤖 AI disabled — skipping tokenizer/model init")
            self.tokenizer = nil
            self.model = nil
            self.endDevotionalId = nil
            self.padId = nil
            self.verseIdId = nil
            self.verseRefId = nil
            self.verseTextId = nil
            self.verseId = nil
            self.startCommentaryId = nil
        }

        // Initialize Enhanced Bible Database
        do {
            print("🔍 Looking for enhanced_bible_kjv.db in main bundle...")

            // First try in main bundle (iOS copies Resources files here)
            if let dbURL = Bundle.main.url(forResource: "enhanced_bible_kjv", withExtension: "db") {
                print("📚 Found Enhanced Bible Database: \(dbURL.path)")
                self.enhancedDatabase = EnhancedBibleDatabase(databasePath: dbURL.path)

                if self.enhancedDatabase?.open() == true {
                    print("✅ Enhanced Bible Database initialized successfully")

                    // Test database connection with multiple checks
                    let testBooks = self.enhancedDatabase?.getAllBooks()
                    print("📊 Database test: Found \(testBooks?.count ?? 0) books")

                    // Run comprehensive database test
                    if self.enhancedDatabase?.testDatabaseConnection() == true {
                        print("🎯 Enhanced Bible Database is fully functional and ready for use")
                    } else {
                        print("⚠️ Enhanced Bible Database opened but connection test failed")
                    }
                } else {
                    print("❌ Failed to open Enhanced Bible Database - check file permissions and format")
                    self.enhancedDatabase = nil
                }
            } else {
                print("❌ Could not find enhanced_bible_kjv.db in main bundle")

                // List all .db files in the bundle for debugging
                if let bundlePath = Bundle.main.bundlePath as String? {
                    do {
                        let fileManager = FileManager.default
                        let contents = try fileManager.contentsOfDirectory(atPath: bundlePath)
                        let dbFiles = contents.filter { $0.hasSuffix(".db") }
                        print("📁 Available .db files in main bundle: \(dbFiles)")
                    } catch {
                        print("❌ Error listing bundle directory: \(error)")
                    }
                }

                self.enhancedDatabase = nil
            }
        }

        self.isReady = true // For testing purposes
    }

    // MARK: - Alternative Prompt Builders

    /// Python-exact prompt builder (matches Python script exactly)
    private func prepareSinglePassPrompt_PythonExact(ref: String, verseText: String) throws -> [Int] {
        guard let tokenizer = self.tokenizer else {
            throw NSError(domain: "BibleCommentaryGenerator", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: "Tokenizer not initialized"])
        }

        // Match Python script exactly:
        // input_text = f"[VERSE_ID]{verse_id}[VERSE_REF]{verse_id}[VERSE_TEXT]{verse_text}[VERSE][START_COMMENTARY]"
        // input_ids = self.tokenizer.encode(input_text, add_special_tokens=False)

        let norm = normalizeVerseId(ref)
        let inputText = "[VERSE_ID]\(norm)[VERSE_REF]\(ref)[VERSE_TEXT]\(verseText)[VERSE][START_COMMENTARY]"

        // Encode the entire string at once (no special tokens added) - matches Python add_special_tokens=False
        let ids = tokenizer.encode(inputText)

        // Debug logging
        print("🐍 Python-exact prompt (matches Python script):")
        print("  Input text: '\(inputText)'")
        print("  Total prompt tokens: \(ids.count)")
        print("  First 10 token IDs: \(ids.prefix(10))")

        return ids
    }

    // Required methods that the bridge expects
    public func prepareSinglePassPrompt(for verseRef: String, verseText: String) throws -> [Int] {
        if usePythonExactPrompt {
            // Use Python-exact format (matches training data exactly)
            return try prepareSinglePassPrompt_PythonExact(ref: verseRef, verseText: verseText)
        } else {
            // Fallback to string-based format
            guard let tokenizer = self.tokenizer else {
                throw NSError(domain: "BibleCommentaryGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tokenizer not initialized"])
            }

            // Parse verse reference (e.g., "Genesis 1:1" -> "GENESIS_1_1")
            let normalizedRef = normalizeVerseId(verseRef)

            // Build prompt exactly like Python test format (no extra spaces/newlines)
            let promptText = "[VERSE_ID]\(normalizedRef)[VERSE_REF]\(verseRef)[VERSE_TEXT]\(verseText)[VERSE][START_COMMENTARY]"

            // Encode to token IDs
            return tokenizer.encode(promptText)
        }
    }

    public func postProcessGeneratedText(_ raw: String) -> (commentary: String, devotional: String, isTruncated: Bool, safetyFlags: [String]) {
        var safetyFlags: [String] = []

        // Split on [START_DEVOTIONAL] to separate commentary and devotional
        let components = raw.components(separatedBy: "[START_DEVOTIONAL]")

        if components.count >= 2 {
            // Has both commentary and devotional
            var commentaryRaw = components[0]
            var devotionalRaw = components[1]

            // Clean up markers - remove [END_COMMENTARY] from commentary
            commentaryRaw = commentaryRaw
                .replacingOccurrences(of: "[END_COMMENTARY]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove [END_DEVOTIONAL] from devotional
            devotionalRaw = devotionalRaw
                .replacingOccurrences(of: "[END_DEVOTIONAL]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return (commentaryRaw, devotionalRaw, false, safetyFlags)
        } else {
            // Fallback: treat all as commentary
            safetyFlags.append("No START_DEVOTIONAL marker found")
            let commentaryRaw = raw
                .replacingOccurrences(of: "[END_COMMENTARY]", with: "")
                .replacingOccurrences(of: "[END_DEVOTIONAL]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return (commentaryRaw, "", false, safetyFlags)
        }
    }

    // Method expected by IntegrationTest
    public func generateCommentary(for verseRef: String, verseText: String) async -> String {
        // 🔒 Always use database-only generation - no AI/ML fallback
        if let dbResult = await generateCommentaryFromDatabaseOnly(for: verseRef) {
            return dbResult
        } else {
            return "No commentary available for \(verseRef) in database"
        }
    }

    /// ✅ Database-first generation method - uses EnhancedBibleDatabase for lookup
    public func generateCommentaryFromDatabase(for verseRef: String, verseText: String) async -> String {
        // First, try to generate from database lookup
        if let dbCommentary = await generateFromDatabaseLookup(ref: verseRef) {
            #if DEBUG
            print("📚 Database lookup successful for: \(verseRef)")
            #endif
            return dbCommentary
        }

        // Fallback to ML generation if database lookup fails
        #if DEBUG
        print("⚠️ Database lookup failed for: \(verseRef), falling back to ML generation")
        #endif

        return await generateCommentary(for: verseRef, verseText: verseText)
    }

    /// ✅ Database-only generation method - uses ONLY EnhancedBibleDatabase, no ML fallback
    /// Simplified database-only generation - just needs verse reference
    public func generateCommentaryFromDatabaseOnly(for verseRef: String) async -> String? {
        // Only try to generate from database lookup, no ML fallback
        if let dbCommentary = await generateFromDatabaseLookup(ref: verseRef) {
            #if DEBUG
            print("📚 Database-only lookup successful for: \(verseRef)")
            #endif
            return dbCommentary
        }

        #if DEBUG
        print("⚠️ Database-only lookup failed for: \(verseRef) - no content available")
        #endif

        return nil // Return nil if no database content found
    }

    /// Private method to lookup commentary from EnhancedBibleDatabase
    private func generateFromDatabaseLookup(ref: String) async -> String? {
        guard let database = self.enhancedDatabase else {
            #if DEBUG
            print("❌ Enhanced Bible Database not available")
            #endif
            return nil
        }

        // Parse verse reference (e.g., "Genesis 1:1" -> book: "Genesis", chapter: 1, verse: 1)
        let components = ref.split(separator: " ")
        guard components.count >= 2 else {
            #if DEBUG
            print("❌ Could not parse verse reference: \(ref)")
            #endif
            return nil
        }

        let bookName = String(components[0..<components.count-1].joined(separator: " "))
        let chapterVerse = components.last!.split(separator: ":")
        guard chapterVerse.count == 2,
              let chapter = Int(chapterVerse[0]),
              let verse = Int(chapterVerse[1]) else {
            #if DEBUG
            print("❌ Could not parse chapter:verse from: \(components.last!)")
            #endif
            return nil
        }

        // Lookup verse by reference
        guard let verseData = database.getVerseByReference(bookName: bookName, chapterNumber: chapter, verseNumber: verse) else {
            #if DEBUG
            print("❌ Verse not found in database: \(ref)")
            #endif
            return nil
        }

        // Get commentary for the verse
        guard let commentary = database.getCommentaryForVerse(verseId: verseData.id) else {
            #if DEBUG
            print("❌ No commentary found for verse: \(ref)")
            #endif
            return nil
        }

        // Build the response with enhanced commentary and devotional summary
        var response = ""

        // Add enhanced commentary if available
        if !commentary.enhancedCommentary.isEmpty {
            response += commentary.enhancedCommentary
        } else {
            #if DEBUG
            print("⚠️ No commentary content available for: \(ref)")
            #endif
            return nil
        }

        // Add devotional summary if available
        if !commentary.devotionalSummary.isEmpty {
            response += "\n\n**Devotional Insight:**\n\(commentary.devotionalSummary)"
        }

        return response
    }

    // Method expected by IntegrationTest
    public func inspectModelShapes() {
        // 🚫 Only run if AI features are available
        guard FeatureGate.aiAvailable else {
            Log.info("🤖 AI disabled — skipping model shape inspection")
            return
        }

        guard let model = self.model else {
            Log.ml("Model not initialized")
            return
        }

        Log.ml("=== Model Shape Inspection ===")
        let desc = model.modelDescription
        Log.ml("Model: \(desc.metadata[.creatorDefinedKey] ?? "Unknown")")
        Log.ml("Input descriptions:")
        for (name, inputDesc) in desc.inputDescriptionsByName {
            Log.ml("  \(name): \(inputDesc)")
        }
        Log.ml("Output descriptions:")
        for (name, outputDesc) in desc.outputDescriptionsByName {
            Log.ml("  \(name): \(outputDesc)")
        }
    }

    // Helper method to normalize verse reference
    private func normalizeVerseId(_ verseRef: String) -> String {
        // Parse "Book X:Y" format
        let components = verseRef.split(separator: " ")
        guard components.count >= 2 else { return verseRef }

        let book = components[0..<components.count-1].joined(separator: "_").uppercased()
        let chapterVerse = components.last!.split(separator: ":")
        guard chapterVerse.count == 2 else { return verseRef }

        return "\(book)_\(chapterVerse[0])_\(chapterVerse[1])"
    }
}

extension BibleCommentaryGenerator {
    // Keep your existing loader and tokenizer setup.
    // Use this buffered single-pass bridge for generation.

    func generateSinglePassBuffered(ref: String, verseText: String) async throws -> String {
        // 🚫 AI/ML functionality is disabled - use DB-only generation
        return await generateCommentaryFromDatabaseOnly(for: ref) ?? "No commentary available for \(ref)"
    }
}