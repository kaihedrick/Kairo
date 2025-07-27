// filepath: BibleAppPOCV2/OptimizedBibleApp.swift
import SwiftUI

@main
struct OptimizedBibleApp: App {
    // BARTService will be initialized when needed in VerseSummaryViewModel
    
    init() {
        print("🚀 BibleAppPOCV2 starting up...")
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