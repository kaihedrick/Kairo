import Foundation
import CoreGraphics

/// Common layout constants shared between views and paginator.
struct LayoutMetrics {
    /// Horizontal padding applied to each side of a page.
    static let horizontalPagePadding: CGFloat = 24
    /// Vertical padding applied to the top and bottom of a page.
    /// Increased to be more conservative and account for any UI elements
    static let verticalPagePadding: CGFloat = 24
}
