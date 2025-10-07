// MARK: - Feature Flags
// Build-time and runtime feature control system

enum FeatureFlags {
    // AI/ML functionality - hard-off by default
    // Set to true only if you want to re-enable AI features
    static let aiEnabled: Bool = false

    // Database functionality - always enabled
    static let databaseEnabled: Bool = true

    // Navigation features
    static let enhancedNavigation: Bool = true
    static let historyEnabled: Bool = true

    // UI features
    static let liquidGlassEnabled: Bool = true
    static let glassEffectsEnabled: Bool = true
}

// MARK: - Build-time Feature Detection

#if AI_FEATURES
let buildHasAI = true
#else
let buildHasAI = false
#endif

// MARK: - Feature Gate Helpers

struct FeatureGate {
    static var aiAvailable: Bool {
        FeatureFlags.aiEnabled && buildHasAI
    }

    static var databaseAvailable: Bool {
        FeatureFlags.databaseEnabled
    }
}

// MARK: - Gated Logging System

enum LogTopic {
    case app, db, paging, nav, ml
}

struct Log {
    static var enableML = false // hard-off for ML logs

    static func ml(_ message: @autoclosure () -> String) {
        guard enableML, FeatureGate.aiAvailable else { return }
        print(message())
    }

    static func info(_ message: String) {
        print("ℹ️ \(message)")
    }

    static func error(_ message: String) {
        print("❌ \(message)")
    }

    static func success(_ message: String) {
        print("✅ \(message)")
    }
}

// MARK: - Verbose Debug Logging Controls

#if DEBUG
struct VerboseLogs {
    /// Navigation and page history logging (disable for performance)
    static var nav = false
    
    /// Page generation and layout logging
    static var paging = false
    
    /// Database query logging
    static var db = false
    
    /// ViewModel state changes
    static var viewModel = false
}
#endif
