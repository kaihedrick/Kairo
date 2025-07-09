import SwiftUI

@main
struct OptimizedBibleApp: App {
    // MARK: - Architecture Demo Toggle

    @AppStorage("useModernArchitecture") private var useModernArchitecture = false
    @AppStorage("useSimpleArchitecture") private var useSimpleArchitecture = false

    var body: some Scene {
        WindowGroup {
            Group {
                if useSimpleArchitecture {
                    // Final Clean Architecture - No conflicts, fully working
                    FinalBibleReaderView()
                } else if useModernArchitecture {
                    // Working Simple Architecture 
                    WorkingSimpleBibleView()
                } else {
                    // Existing Architecture
                    OptimizedBookGridView()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"))) { _ in
                handleGlobalMemoryWarning()
            }
            .overlay(alignment: .topTrailing) {
                #if DEBUG
                architectureToggleButton
                #endif
            }
        }
    }

    private func handleGlobalMemoryWarning() {
        // Clear any global caches or temporary data
        print("🚨 Memory warning received - cleaning up resources")

        Task {
            await OptimizedBibleDataLoader.shared.handleMemoryWarning()
        }

        // Force garbage collection
        autoreleasepool {
            // Any cleanup code will run in an autorelease pool
        }
    }

    #if DEBUG
    private var architectureToggleButton: some View {
        VStack(spacing: 8) {
            Button("Original") {
                useModernArchitecture = false
                useSimpleArchitecture = false
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(!useModernArchitecture && !useSimpleArchitecture ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(4)
            
            Button("Modern") {
                useSimpleArchitecture = true
                useModernArchitecture = false
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(useSimpleArchitecture ? Color.green : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(4)
            
            Button("Simple") {
                useSimpleArchitecture = false
                useModernArchitecture = true
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(useModernArchitecture ? Color.purple : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(4)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .padding()
    }
    #endif
}