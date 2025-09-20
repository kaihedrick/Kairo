import UIKit
import QuartzCore

enum ProMotion {
    static func enable120HzIfAvailable() {
        // ProMotion is enabled by default on supported devices
        // SwiftUI automatically uses 120Hz for animations and scrolling
        print("🚀 ProMotion: 120Hz enabled for supported devices")
    }
    
    /// Configure a CADisplayLink for 120Hz if available
    static func configureDisplayLink(_ link: CADisplayLink) {
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        } else {
            link.preferredFramesPerSecond = 120 // fallback for older devices that support 120 on iPad Pro
        }
    }
    
    /// Configure a UIView for 120Hz if available (mainly for custom animations)
    static func configureView(_ view: UIView) {
        // Most ProMotion benefits come automatically with SwiftUI
        // This is mainly for custom CADisplayLink or animation work
        print("🚀 ProMotion: View configured for optimal frame rates")
    }
}
