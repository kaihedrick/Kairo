// filepath: BibleAppPOCV2/OptimizedBibleApp.swift
import SwiftUI

// MARK: - Performance Testing Stub
class PerformanceTestTimer: ObservableObject {
    func testChapterLoadingPerformance(book: String, chapters: [Int]) async {
        // Stub implementation - performance testing disabled
    }

    func testOnScreenReaderPerformance(book: String, chapter: Int) async {
        // Stub implementation - performance testing disabled
    }

    func generatePerformanceReport() -> String {
        return "Performance testing is currently disabled."
    }

    func clearMeasurements() {
        // Stub implementation
    }
}

@main
struct OptimizedBibleApp: App {

    // Core ML BibleCommentaryGenerator will be initialized when needed

    init() {
        print("🚀 BibleAppPOCV2 starting up...")
        
        // Enable ProMotion 120Hz if available
        ProMotion.enable120HzIfAvailable()

        // 🔬 ML inspection only when AI features are enabled and in DEBUG mode
        // Runs in background to avoid blocking main thread during startup
        #if DEBUG
        if FeatureGate.aiAvailable {
            DispatchQueue.global(qos: .utility).async {
                IntegrationTest.inspectModelShapes()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            OptimizedBookGridView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    handleGlobalMemoryWarning()
                }
        }
    }

    private func handleGlobalMemoryWarning() {
        // Clear any global caches or temporary data
        print("🚨 Memory warning received - cleaning up resources")

        Task { @MainActor in
            let dataLoader = DatabaseBibleDataLoader.shared
            await dataLoader.clearCache()
        }

        // Force garbage collection
        autoreleasepool {
            // Any cleanup code will run in an autorelease pool
        }
    }
}
