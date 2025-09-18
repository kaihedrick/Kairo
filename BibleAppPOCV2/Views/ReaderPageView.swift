// filepath: BibleAppPOCV2/Views/ReaderPageView.swift
// ReaderPageView.swift
// Non-scrolling page view with exact verse tapping

import UIKit
import Foundation

/// Non-scrolling page view with exact verse tapping
final class ReaderPageView: UIView {
    private let textView = UITextView()
    private var layout: NSLayoutManager!
    private var container: NSTextContainer!
    private var verseMap: [(NSRange, VerseKey)] = []
    private var onTap: ((VerseKey) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTextView()
    }
    
    required init?(coder: NSCoder) { 
        fatalError("init(coder:) has not been implemented") 
    }
    
    private func setupTextView() {
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        addSubview(textView)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
    }
    
    func configure(text: NSAttributedString,
                   storage: NSTextStorage,
                   layout: NSLayoutManager,
                   container: NSTextContainer,
                   verseMap: [(NSRange, VerseKey)],
                   onTap: @escaping (VerseKey) -> Void) {
        textView.attributedText = text
        self.layout = layout
        self.container = container
        self.verseMap = verseMap
        self.onTap = onTap
        addTapRecognizer()
    }
    
    private func addTapRecognizer() {
        // Remove existing tap recognizers
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        
        // Make taps require ScrollView pan to fail (so swipes win)
        DispatchQueue.main.async { [weak self] in
            if let scrollView = self?.findEnclosingScrollView() {
                tap.require(toFail: scrollView.panGestureRecognizer)
            }
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let onTap = onTap else { return }
        
        let loc = gesture.location(in: textView)
        let inset = textView.textContainerInset
        let point = CGPoint(x: loc.x - inset.left, y: loc.y - inset.top)
        
        let glyph = layout.glyphIndex(for: point, in: container)
        let char = layout.characterIndexForGlyph(at: glyph)
        
        if let hit = verseMap.first(where: { NSLocationInRange(char, $0.0) }) {
            onTap(hit.1)
        }
    }
    
    private func findEnclosingScrollView() -> UIScrollView? {
        var view: UIView? = self
        while let current = view?.superview {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current
        }
        return nil
    }
}
