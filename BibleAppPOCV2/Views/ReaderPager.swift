// filepath: BibleAppPOCV2/Views/ReaderPager.swift
// ReaderPager.swift
// SwiftUI wrapper for the fixed page reader

import SwiftUI
import UIKit

/// SwiftUI wrapper for the fixed page reader
struct ReaderPager: UIViewControllerRepresentable {
    let body: NSAttributedString
    let pages: [ReaderPage]
    let pageSize: CGSize
    var onTapVerse: (VerseKey) -> Void
    
    func makeUIViewController(context: Context) -> ReaderPagerViewController {
        ReaderPagerViewController()
    }
    
    func updateUIViewController(_ uiVC: ReaderPagerViewController, context: Context) {
        uiVC.onTapVerse = onTapVerse
        uiVC.configure(body: body, pages: pages, pageSize: pageSize)
    }
}
