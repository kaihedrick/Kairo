// filepath: BibleAppPOCV2/Views/ReaderPagerViewController.swift
// ReaderPagerViewController.swift
// UIPageViewController for horizontal paging with exact verse tapping

import UIKit
import Foundation

/// UIPageViewController for horizontal paging with exact verse tapping
final class ReaderPagerViewController: UIPageViewController, UIPageViewControllerDataSource {
    private var storage: NSTextStorage!
    private var layout: NSLayoutManager!
    private var containers: [NSTextContainer] = []
    private var pages: [ReaderPage] = []
    private var body: NSAttributedString = .init(string: "")
    var onTapVerse: ((VerseKey) -> Void)?
    
    init() {
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
        dataSource = self
    }
    
    required init?(coder: NSCoder) { 
        fatalError("init(coder:) has not been implemented") 
    }
    
    func configure(body: NSAttributedString, pages: [ReaderPage], pageSize: CGSize) {
        self.body = body
        self.pages = pages
        
        storage = NSTextStorage(attributedString: body)
        layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        
        containers = pages.map { _ in
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            return container
        }
        
        setViewControllers([pageVC(at: 0)], direction: .forward, animated: false)
    }
    
    private func pageVC(at index: Int) -> UIViewController {
        let vc = ReaderPageVC()
        let page = pages[index]
        let sub = body.attributedSubstring(from: page.range)
        vc.configure(
            text: sub,
            storage: storage,
            layout: layout,
            container: containers[index],
            verseMap: page.verseMap,
            onTap: { [weak self] key in
                self?.onTapVerse?(key)
            }
        )
        return vc
    }
    
    // MARK: - UIPageViewControllerDataSource
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let idx = index(of: viewController), idx > 0 else { return nil }
        return pageVC(at: idx - 1)
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let idx = index(of: viewController), idx + 1 < pages.count else { return nil }
        return pageVC(at: idx + 1)
    }
    
    private func index(of vc: UIViewController) -> Int? {
        return viewControllers?.firstIndex(of: vc)
    }
}
