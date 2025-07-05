// TextMeasurer.swift
// Measures an AttributedString within a maxSize envelope.

import Foundation
import UIKit

struct TextMeasurer {
    /// Measure an attributed string using TextKit 1 APIs.
    static func measure(_ text: AttributedString, size: CGSize) -> CGSize {
        guard !text.characters.isEmpty else { return .zero }

        let nsAttr = NSAttributedString(text)
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let rect = nsAttr.boundingRect(
            with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
            options: options,
            context: nil
        )
        let width = min(size.width, ceil(rect.width))
        let height = min(size.height, ceil(rect.height))
        return CGSize(width: width, height: height)
    }

    /// Split the text so the head fits within `size` and return the remainder.
    static func split(_ text: AttributedString, size: CGSize) -> (AttributedString, AttributedString) {
        if text.characters.isEmpty { return (.init(), .init()) }

        let nsAttr = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let storage = NSTextStorage(attributedString: nsAttr)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: size)
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        layout.glyphRange(for: container)
        let glyphRange = layout.glyphRange(forBoundingRect: CGRect(origin: .zero, size: size), in: container)
        let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let fit = nsAttr.attributedSubstring(from: charRange)
        let restLocation = charRange.location + charRange.length
        let restLength = nsAttr.length - restLocation
        let rest = restLength > 0 ? nsAttr.attributedSubstring(from: NSRange(location: restLocation, length: restLength)) : NSAttributedString()

        return (AttributedString(fit), AttributedString(rest))
    }
}
