import SwiftUI

@main
struct OptimizedBibleApp: App {
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
            await OptimizedBibleDataLoader.shared.handleMemoryWarning()
        }
        
        // Force garbage collection
        autoreleasepool {
            // Any cleanup code will run in an autorelease pool
        }
    }
}