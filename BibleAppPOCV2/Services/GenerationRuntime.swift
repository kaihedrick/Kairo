// filepath: BibleAppPOCV2/Services/GenerationRuntime.swift
import Foundation
import Combine
import NotificationCenter

enum InferenceMode { case coreml, fallback }

@MainActor
final class GenerationRuntime {
    static let shared = GenerationRuntime()
    private init() {}

    // Single source of truth: BibleCommentaryGenerator's readiness
    var mode: InferenceMode {
        return BibleCommentaryGenerator.shared.isReady ? .coreml : .fallback
    }

    // Notification names for runtime mode changes (for backward compatibility)
    static let runtimeModeChangedNotification = Notification.Name("GenerationRuntimeModeChanged")
    static let runtimeModeKey = "runtimeMode"

    // Method to check if CoreML is available and ready
    func isCoreMLReady() -> Bool {
        return BibleCommentaryGenerator.shared.isReady
    }

    // LEGACY: These methods are kept for backward compatibility but are no-ops
    // The actual readiness state is managed by BibleCommentaryGenerator
    func switchToCoreML() {
        // BibleCommentaryGenerator manages this now
        print("⚠️ GenerationRuntime.switchToCoreML() is deprecated - BibleCommentaryGenerator manages readiness")
    }

    func switchToFallback() {
        // BibleCommentaryGenerator manages this now
        print("⚠️ GenerationRuntime.switchToFallback() is deprecated - BibleCommentaryGenerator manages readiness")
    }

    // Computed property for backward compatibility
    var currentMode: InferenceMode {
        return mode
    }
}


