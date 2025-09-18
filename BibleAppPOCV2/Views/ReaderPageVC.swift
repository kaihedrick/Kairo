// filepath: BibleAppPOCV2/Views/ReaderPageVC.swift
// ReaderPageVC.swift
// Page view controller for individual pages

import UIKit
import Foundation

/// Page view controller for individual pages
final class ReaderPageVC: UIViewController {
    private let pageView = ReaderPageView()
    
    override func loadView() { 
        view = pageView 
    }
    
    func configure(text: NSAttributedString,
                   storage: NSTextStorage,
                   layout: NSLayoutManager,
                   container: NSTextContainer,
                   verseMap: [(NSRange, VerseKey)],
                   onTap: @escaping (VerseKey) -> Void) {
        pageView.configure(
            text: text,
            storage: storage,
            layout: layout,
            container: container,
            verseMap: verseMap,
            onTap: onTap
        )
    }
}
