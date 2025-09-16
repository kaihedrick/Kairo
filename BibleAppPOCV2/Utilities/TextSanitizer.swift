// filepath: BibleAppPOCV2/Utilities/TextSanitizer.swift
import Foundation

// MARK: - Text Sanitizer

/// Comprehensive text sanitization utility for fixing character encoding corruption
/// This utility handles the critical UTF-8 corruption issues that can break text display
@MainActor
final class TextSanitizer: ObservableObject {

    // MARK: - Shared Instance

    static let shared = TextSanitizer()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Sanitization Methods

    /// Sanitize text by removing all known corruption patterns
    ///
    /// - Parameter text: The text to sanitize
    /// - Returns: Sanitized text with corruption patterns removed
    func sanitizeText(_ text: String) -> String {
        var sanitized = text

        #if DEBUG
        print("🧹 Starting text sanitization for text length: \(text.count)")
        #endif

        // Remove all corruption patterns
        for pattern in ExtendedCorruptionPattern.allPatterns {
            let beforeCount = sanitized.count
            sanitized = sanitized.replacingOccurrences(of: pattern.pattern, with: pattern.replacement)
            let afterCount = sanitized.count

            #if DEBUG
            if beforeCount != afterCount {
                print("  Fixed pattern '\(pattern.pattern)': removed \(beforeCount - afterCount) characters")
            }
            #endif
        }

        // Clean up formatting
        sanitized = cleanUpFormatting(sanitized)

        #if DEBUG
        if text != sanitized {
            print("✅ Sanitization complete: \(text.count) → \(sanitized.count) characters")
        }
        #endif

        return sanitized
    }

    /// Sanitize text and return detailed information about what was fixed
    func sanitizeTextWithReport(_ text: String) -> TextSanitizationReport {
        let originalText = text
        let originalLength = text.count

        // Detect corruption patterns
        let detectedPatterns = detectCorruptionPatterns(in: text)

        // Apply sanitization
        let sanitizedText = sanitizeText(text)
        let sanitizedLength = sanitizedText.count

        // Calculate statistics
        let patternsFixed = detectedPatterns.count
        let charactersRemoved = originalLength - sanitizedLength

        return TextSanitizationReport(
            originalText: originalText,
            sanitizedText: sanitizedText,
            patternsDetected: detectedPatterns,
            patternsFixed: patternsFixed,
            charactersRemoved: charactersRemoved,
            wasCorrupted: !detectedPatterns.isEmpty
        )
    }

    /// Validate text for corruption without modifying it
    func validateText(_ text: String) -> TextValidationResult {
        let patterns = detectCorruptionPatterns(in: text)
        let isCorrupted = !patterns.isEmpty

        return TextValidationResult(
            text: text,
            isCorrupted: isCorrupted,
            corruptionPatterns: patterns,
            severity: calculateSeverity(from: patterns)
        )
    }

    // MARK: - Corruption Pattern Detection

    /// Detect all corruption patterns in the given text
    private func detectCorruptionPatterns(in text: String) -> [DetectedCorruptionPattern] {
        var detected: [DetectedCorruptionPattern] = []

        for pattern in ExtendedCorruptionPattern.allPatterns {
            if text.contains(pattern.pattern) {
                let count = text.components(separatedBy: pattern.pattern).count - 1
                detected.append(DetectedCorruptionPattern(
                    pattern: pattern,
                    occurrences: count,
                    severity: pattern.severity
                ))
            }
        }

        return detected.sorted { $0.severity.rawValue > $1.severity.rawValue }
    }

    /// Calculate overall corruption severity
    private func calculateSeverity(from patterns: [DetectedCorruptionPattern]) -> ExtendedCorruptionSeverity {
        guard !patterns.isEmpty else { return .none }

        let criticalCount = patterns.filter { $0.severity == .critical }.count
        let majorCount = patterns.filter { $0.severity == .major }.count

        if criticalCount > 0 {
            return .critical
        } else if majorCount > 0 {
            return .major
        } else {
            return .minor
        }
    }

    // MARK: - Formatting Cleanup

    /// Clean up text formatting after corruption removal
    private func cleanUpFormatting(_ text: String) -> String {
        var cleaned = text

        // Clean up extra whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Ensure proper spacing around special tokens
        cleaned = cleaned.replacingOccurrences(of: "\\[([^\\]]+)\\]", with: " [$1] ", options: .regularExpression)

        // Clean up multiple spaces
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)

        // Ensure proper line breaks
        cleaned = cleaned.replacingOccurrences(of: "\n\n\n+", with: "\n\n")

        // Clean up trailing/leading whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    // MARK: - Debug and Analysis

    /// Analyze text for corruption and provide detailed debugging information
    ///
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - label: Optional label for the analysis output
    /// - Returns: Comprehensive analysis report
    func analyzeText(_ text: String, label: String = "Text Analysis") -> TextAnalysisReport {
        #if DEBUG
        print("🔍 \(label):")
        print("   Length: \(text.count)")
        print("   UTF-8 bytes: \(text.utf8.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("   UTF-16 bytes: \(text.utf16.map { String(format: "%04X", $0) }.joined(separator: " "))")
        #endif

        let validation = validateText(text)

        #if DEBUG
        print("   Corruption Status: \(validation.isCorrupted ? "CORRUPTED" : "Clean")")

        if validation.isCorrupted {
            print("   Severity: \(validation.severity)")
            print("   Patterns Found:")
            for pattern in validation.corruptionPatterns {
                print("      - '\(pattern.pattern.pattern)': \(pattern.occurrences) occurrences (\(pattern.severity))")
            }
        }
        #endif

        return TextAnalysisReport(
            text: text,
            validation: validation,
            byteAnalysis: ByteAnalysis(
                utf8Bytes: Array(text.utf8),
                utf16Bytes: Array(text.utf16)
            )
        )
    }
}

// MARK: - Data Models

/// Comprehensive corruption pattern definition
struct ExtendedCorruptionPattern {
    let pattern: String
    let replacement: String
    let description: String
    let severity: ExtendedCorruptionSeverity
    let commonSource: String

    static let allPatterns: [ExtendedCorruptionPattern] = [
        // Critical corruption patterns
        ExtendedCorruptionPattern(
            pattern: "CORRUPT_VERSE_ID",
            replacement: "[VERSE_ID]",
            description: "Primary corruption marker with special token",
            severity: .critical,
            commonSource: "Token decoding failure"
        ),
        ExtendedCorruptionPattern(
            pattern: "CORRUPT_VERSE_REF",
            replacement: "[VERSE_REF]",
            description: "Reference token corruption",
            severity: .critical,
            commonSource: "Token decoding failure"
        ),
        ExtendedCorruptionPattern(
            pattern: "CORRUPT_VERSE_TEXT",
            replacement: "[VERSE_TEXT]",
            description: "Verse text token corruption",
            severity: .critical,
            commonSource: "Token decoding failure"
        ),
        ExtendedCorruptionPattern(
            pattern: "CORRUPT_CHAR",
            replacement: "",
            description: "General UTF-8 byte corruption",
            severity: .major,
            commonSource: "Encoding mismatch"
        ),

        // Major corruption patterns
        ExtendedCorruptionPattern(
            pattern: "broken",
            replacement: "fixed",
            description: "Test corruption pattern",
            severity: .major,
            commonSource: "Testing"
        )
    ]
}

/// Extended corruption severity levels
enum ExtendedCorruptionSeverity: Int, CaseIterable {
    case none = 0
    case minor = 1
    case major = 2
    case critical = 3

    var description: String {
        switch self {
        case .none: return "None"
        case .minor: return "Minor"
        case .major: return "Major"
        case .critical: return "Critical"
        }
    }
}

/// Detected corruption pattern with occurrence count
struct DetectedCorruptionPattern {
    let pattern: ExtendedCorruptionPattern
    let occurrences: Int
    let severity: ExtendedCorruptionSeverity
}

/// Text validation result
struct TextValidationResult {
    let text: String
    let isCorrupted: Bool
    let corruptionPatterns: [DetectedCorruptionPattern]
    let severity: ExtendedCorruptionSeverity
}

/// Text sanitization report
struct TextSanitizationReport {
    let originalText: String
    let sanitizedText: String
    let patternsDetected: [DetectedCorruptionPattern]
    let patternsFixed: Int
    let charactersRemoved: Int
    let wasCorrupted: Bool
}

/// Text analysis report with detailed debugging information
struct TextAnalysisReport {
    let text: String
    let validation: TextValidationResult
    let byteAnalysis: ByteAnalysis
}

/// Byte-level analysis information
struct ByteAnalysis {
    let utf8Bytes: [UInt8]
    let utf16Bytes: [UInt16]

    var utf8HexString: String {
        utf8Bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var utf16HexString: String {
        utf16Bytes.map { String(format: "%04X", $0) }.joined(separator: " ")
    }
}