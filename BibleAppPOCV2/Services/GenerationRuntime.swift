// filepath: BibleAppPOCV2/Services/GenerationRuntime.swift
import Foundation
import Combine
import NotificationCenter

enum InferenceMode { case coreml, fallback }

@MainActor
final class GenerationRuntime: ObservableObject {
    static let shared = GenerationRuntime()
    private init() {}

    // Default mode until model loads
    @Published private(set) var mode: InferenceMode = .fallback

    // Notification names for runtime mode changes
    static let runtimeModeChangedNotification = Notification.Name("GenerationRuntimeModeChanged")
    static let runtimeModeKey = "runtimeMode"

    /// Called by BibleCommentaryGenerator when readiness changes
    func updateMode(isReady: Bool) {
        let newMode: InferenceMode = isReady ? .coreml : .fallback
        if newMode != mode {
            let oldMode = mode
            mode = newMode
            print("📡 GenerationRuntime: mode changed from \(oldMode) to \(newMode)")

            NotificationCenter.default.post(
                name: Self.runtimeModeChangedNotification,
                object: self,
                userInfo: [Self.runtimeModeKey: newMode]
            )
        }
    }

    /// Quick helper for UI
    func isCoreMLReady() -> Bool {
        return mode == .coreml
    }
}
