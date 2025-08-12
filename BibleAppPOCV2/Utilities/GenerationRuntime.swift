// filepath: BibleAppPOCV2/Utilities/GenerationRuntime.swift
import Foundation
import Combine

@MainActor
final class GenerationRuntime {
    static let shared = GenerationRuntime()
    private init() {}

    // Default to fallback until Core ML is confirmed ready
    @Published var mode: InferenceMode = .fallback
}


