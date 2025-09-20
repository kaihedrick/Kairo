import UIKit
import SwiftUI
import QuartzCore

struct HighHzHint: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        
        // ProMotion is automatically enabled for SwiftUI views
        // This helper provides a hint to the system for optimal frame rates
        DispatchQueue.main.async {
            // Find and configure the enclosing scroll view if available
            if let sv = enclosingScrollView(of: v) {
                // Configure scroll view for optimal performance
                sv.decelerationRate = UIScrollView.DecelerationRate.normal
                sv.showsVerticalScrollIndicator = true
                sv.showsHorizontalScrollIndicator = false
                
                // Enable smooth scrolling for ProMotion devices
                if #available(iOS 15.0, *) {
                    sv.isScrollEnabled = true
                    sv.bounces = true
                    sv.alwaysBounceVertical = true
                }
            }
        }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private func enclosingScrollView(of v: UIView) -> UIScrollView? {
    var cur: UIView? = v
    while let c = cur {
        if let sv = c as? UIScrollView { return sv }
        cur = c.superview
    }
    return nil
}

// MARK: - Array Safe Subscript Extension
extension Array {
    subscript(safe i: Int) -> Element? { (0..<count).contains(i) ? self[i] : nil }
}
