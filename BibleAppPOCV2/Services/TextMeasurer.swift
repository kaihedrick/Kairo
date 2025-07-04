// TextMeasurer.swift
// Measures an AttributedString within a maxSize envelope.

import Foundation
import UIKit

struct TextMeasurer {
    /// Returns the size required to render `text` within `maxSize`.
    static func measure(_ text: AttributedString, maxSize: CGSize) -> CGSize {
        // Avoid CoreFoundation warnings when measuring empty strings
        guard !text.characters.isEmpty else { return .zero }

        // Convert SwiftUI AttributedString → UIKit NSAttributedString
        let nsAttr = NSAttributedString(text)

        // Create a bounding rect calculation with the same text container insets/padding as your UITextView
        let drawingOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let drawingRect = nsAttr.boundingRect(
            with: CGSize(width: maxSize.width, height: .greatestFiniteMagnitude),
            options: drawingOptions,
            context: nil
        )
        
        // Cap the height at maxSize.height
        let h = min(drawingRect.height, maxSize.height)
        // Width will never exceed maxSize.width when using boundingRect
        let w = min(drawingRect.width, maxSize.width)
        
        return CGSize(width: ceil(w), height: ceil(h))
    }
}
