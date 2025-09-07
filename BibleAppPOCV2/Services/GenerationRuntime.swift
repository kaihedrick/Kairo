// filepath: BibleAppPOCV2/Services/GenerationRuntime.swift
import Foundation
import Combine
import NotificationCenter

enum InferenceMode { case coreml, fallback }

@MainActor
final class GenerationRuntime {
    static let shared = GenerationRuntime()
    private init() {}

<<<<<<< HEAD
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
=======
    // Default to fallback until Core ML is confirmed ready
    @Published var mode: InferenceMode = .fallback
    
    // Notification names for runtime mode changes
    static let runtimeModeChangedNotification = Notification.Name("GenerationRuntimeModeChanged")
    static let runtimeModeKey = "runtimeMode"
    
    // Computed property to get current mode
    var currentMode: InferenceMode {
        get { mode }
        set {
            let oldMode = mode
            mode = newValue
            
            // Post notification when mode changes
            if oldMode != newValue {
                print("📡 GenerationRuntime: Posting notification - mode changed from \(oldMode) to \(newValue)")
                NotificationCenter.default.post(
                    name: Self.runtimeModeChangedNotification,
                    object: self,
                    userInfo: [Self.runtimeModeKey: newValue]
                )
                print("📡 GenerationRuntime: Notification posted successfully")
            }
        }
    }
    
    // Method to switch to CoreML mode
    func switchToCoreML() {
        currentMode = .coreml
    }
    
    // Method to switch to fallback mode
    func switchToFallback() {
        currentMode = .fallback
    }
    
    // Method to check if CoreML is available and ready
    func isCoreMLReady() -> Bool {
        // This could be expanded to check actual CoreML model availability
        return mode == .coreml
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
    }
}


