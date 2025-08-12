// filepath: BibleAppPOCV2/Services/GenerationRuntime.swift
import Foundation
import Combine
import NotificationCenter

@MainActor
final class GenerationRuntime {
    static let shared = GenerationRuntime()
    private init() {}

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
                NotificationCenter.default.post(
                    name: Self.runtimeModeChangedNotification,
                    object: self,
                    userInfo: [Self.runtimeModeKey: newValue]
                )
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
    }
}


