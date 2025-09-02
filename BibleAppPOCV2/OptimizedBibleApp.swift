// filepath: BibleAppPOCV2/OptimizedBibleApp.swift
import SwiftUI

@main
struct OptimizedBibleApp: App {
    // Core ML BibleCommentaryGenerator will be initialized when needed
    
    init() {
        print("🚀 BibleAppPOCV2 starting up...")

        // 🔬 Inspect Core ML model shapes for debugging (only in DEBUG mode)
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            IntegrationTest.inspectModelShapes()
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            OptimizedBookGridView()
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"))) { _ in
                    handleGlobalMemoryWarning()
                }
        }
    }

    private func handleGlobalMemoryWarning() {
        // Clear any global caches or temporary data
        print("🚨 Memory warning received - cleaning up resources")

        Task {
            let dataLoader = OptimizedBibleDataLoader()
            await dataLoader.handleMemoryWarning()
        }

        // Force garbage collection
        autoreleasepool {
            // Any cleanup code will run in an autorelease pool
        }
    }
}