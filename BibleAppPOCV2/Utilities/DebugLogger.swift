import CoreGraphics

enum DebugLogger {
    static var isEnabled = true

    static func log(_ message: String) {
        guard isEnabled else { return }
        print("🔍 \(message)")
    }

    static func logMeasurement(container: CGSize, content: CGSize) {
        log("📏 Container: \(container), Content: \(content)")
    }
}
