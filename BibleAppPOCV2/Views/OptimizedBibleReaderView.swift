// filepath: BibleAppPOCV2/Views/OptimizedBibleReaderView.swift
// filepath: BibleAppPOCV2/Views/OptimizedBibleReaderView.swift
import SwiftUI

struct OptimizedBibleReaderView: View {
    @StateObject private var generator = OnDemandPageGenerator(pageSize: CGSize.zero)
    let initialVerse: (book: String, chapter: Int, verse: Int)
    @Environment(\.scenePhase) private var scenePhase
    @State private var sizeChangeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            // Account for navigation bar height (~44pts) and safe areas
            let navigationBarHeight: CGFloat = 44
            let availableHeight = geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - navigationBarHeight
            let size = CGSize(
                width: geo.size.width,
                height: max(availableHeight, 100) // Ensure minimum height
            )
            
            #if DEBUG
            // Debug: Print size calculation details
            let _ = print("📐 Size calc: total=\(geo.size.height), top=\(geo.safeAreaInsets.top), bottom=\(geo.safeAreaInsets.bottom), nav=\(navigationBarHeight), final=\(size.height)")
            #endif

            ZStack {
                if let fragmentedPage = generator.currentFragmentedPage {
                    fragmentedPageView(fragmentedPage, size: size)
                } else if let page = generator.currentPage {
                    pageView(page, size: size)
                } else {
                    ProgressView()
                }
#if DEBUG
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1, perform: {
                        Task { print("X-RAY:\t", await generator.debugInfo()) }
                    })
#endif
            }
            .onAppear {
                print("📐 View appeared, size: \(size)")
                // Size change handler will trigger page generation
            }
            .onChange(of: size) { _, newSize in
                print("📐 Size changed to: \(newSize)")
                
                // Only generate if size is reasonable
                guard newSize.width > 100 && newSize.height > 100 else { return }
                
                // Cancel any pending size change task
                sizeChangeTask?.cancel()
                
                // Debounce size changes to prevent duplicate generation
                sizeChangeTask = Task {
                    // Wait a short time to see if more size changes come in
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    
                    // Check if task was cancelled (another size change occurred)
                    guard !Task.isCancelled else { return }
                    
                    print("📖 DEBOUNCED: Generating fresh fragmented page with size: \(newSize)")
                    generator.updatePageSize(newSize)
                    
                    // Get current position, then force regenerate using fragment approach
                    let currentStart: VerseReference
                    if let fragmentedStart = generator.currentFragmentedPage?.startVerse {
                        currentStart = fragmentedStart
                    } else if let pageStart = generator.currentPage?.startVerse,
                              let verseRef = VerseReference(book: pageStart.book, chapter: pageStart.chapter, verse: pageStart.verse) {
                        currentStart = verseRef
                    } else {
                        currentStart = VerseReference(book: initialVerse.book, chapter: initialVerse.chapter, verse: initialVerse.verse)!
                    }
                    await generator.generateFragmentedPage(startingAt: (currentStart.book, currentStart.chapter, currentStart.verse))
                }
            }
        }
        .navigationTitle(generator.currentFragmentedPage?.navTitle ?? generator.currentPage?.navTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { generator.handleMemoryPressure() }
        }
        .onDisappear {
            sizeChangeTask?.cancel()
        }
    }

    private func pageView(_ page: OptimizedPageSlice, size: CGSize) -> some View {
        Text(page.content)
            .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
            .padding(.vertical, LayoutMetrics.verticalPagePadding)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .clipped()
            .onTapGesture { location in
                handleVerseTap(location: location, page: page, size: size)
            }
            .background(
                GeometryReader { textGeo in
                    Color.clear
                        .onAppear {
                            let actualContentHeight = textGeo.size.height
                            let availableHeight = size.height
                            print("📏 RENDER VERIFICATION: content=\(actualContentHeight) vs available=\(availableHeight)")
                            print("📊 VERSE RANGE: \(page.verseKeys.count) verses from \(page.startVerse.description) to \(page.endVerse.description)")
                            
                            // With precision pagination, overflow should be extremely rare
                            if actualContentHeight > availableHeight + 5 { // Very small tolerance
                                print("⚠️ UNEXPECTED OVERFLOW: Content is \(actualContentHeight - availableHeight)pts too tall")
                                print(" This indicates the measurement system needs refinement")
                                // No longer calling reportOverflow - precision pagination should prevent this
                            } else {
                                print("✅ PRECISION SUCCESS: Content fits perfectly within available space")
                                print("📏 VERIFIED: \(page.verseKeys.count) verses fit in \(availableHeight) pts")
                            }
                        }
                        .onChange(of: textGeo.size.height) { _, newHeight in
                            print("📏 CONTENT HEIGHT CHANGED: \(newHeight)")
                        }
                }
            )
#if DEBUG
            .overlay(alignment: .bottom) { Color.red.frame(height: 6) }
#endif
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < -50 {
                            Task { await generator.goToNextPage() }
                        } else if value.translation.width > 50 {
                            Task { await generator.goToPreviousPage() }
                        }
                    }
            )
    }
    
    /// Handles tap on text to show summary for the tapped verse
    private func handleVerseTap(location: CGPoint, page: OptimizedPageSlice, size: CGSize) {
        // Find the verse that was tapped based on location
        guard let tappedVerse = findVerseAtLocation(location: location, page: page, size: size) else {
            print("⚠️ No verse found at tap location")
            return
        }
        
        // Get the verse text from the Bible data - extract ONLY the specific verse
        Task {
            let verseText = await extractVerseText(for: tappedVerse, from: String(page.content.characters))
            
            // Create a complete verse string that includes both reference and text
            // This format matches what the VerseSummaryViewModel.parseVerse function expects
            let completeVerseString = "\(tappedVerse.description) \(verseText)"
            
            print("🎯 Tapped verse: \(tappedVerse.description)")
            print("📝 Complete verse string: '\(completeVerseString.prefix(100))...'")
            print("📝 Extracted text length: \(verseText.count) characters")
            
            // TODO: Show verse summary popup
            // For now, just log the extracted verse
            print("📖 Verse text: '\(verseText.prefix(100))...'")
        }
    }
    
    /// Finds the verse at the given tap location
    private func findVerseAtLocation(location: CGPoint, page: OptimizedPageSlice, size: CGSize) -> VerseKey? {
        // Calculate which verse was tapped based on vertical position
        let tapY = location.y
        let pageHeight = size.height
        let verseCount = page.verseKeys.count
        
        if verseCount == 0 { return nil }
        
        // Calculate verse height and find which verse was tapped
        let verseHeight = pageHeight / CGFloat(verseCount)
        let verseIndex = Int(tapY / verseHeight)
        
        // Ensure index is within bounds
        let clampedIndex = max(0, min(verseIndex, verseCount - 1))
        let tappedVerse = page.verseKeys[clampedIndex]
        
        print("📍 Tap at Y: \(tapY), page height: \(pageHeight), verse count: \(verseCount)")
        print("🎯 Calculated verse index: \(clampedIndex), selected: \(tappedVerse.description)")
        
        return tappedVerse
    }
    
    /// Extracts the text for a specific verse from the page content
    private func extractVerseText(for verse: VerseKey, from content: String) async -> String {
        // Instead of trying to parse the combined content, we should get the verse text
        // directly from the Bible data loader for the specific verse
        // This ensures we get exactly the verse we want, not parsed content from the page
        
        // Load the specific verse text from the Bible data
        if let verseText = await loadSpecificVerseText(for: verse) {
            print("✅ Loaded specific verse text for \(verse.description): '\(verseText.prefix(50))...'")
            return verseText
        }
        
        // Fallback: try to extract by looking for verse numbers in the content
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("\(verse.verse) ") {
                let verseText = String(trimmedLine.dropFirst("\(verse.verse) ".count))
                print("✅ Found verse \(verse.verse) in line: '\(verseText.prefix(50))...'")
                return verseText
            }
        }
        
        // Last resort: return a small portion of content around where the verse should be
        print("⚠️ Could not extract specific verse text, returning limited content")
        let words = content.components(separatedBy: .whitespaces)
        let maxWords = min(20, words.count)
        return words.prefix(maxWords).joined(separator: " ")
    }
    
    /// Loads the specific verse text from the Bible data loader
    private func loadSpecificVerseText(for verse: VerseKey) async -> String? {
        // Use the legacy loader that has a loadVerse method for single verses
        let loader = LegacyOptimizedBibleDataLoader()
        
        // Load ONLY the specific verse, not the whole chapter
        guard let verseData = await loader.loadVerse(book: verse.book, chapter: verse.chapter, verse: verse.verse) else {
            print("❌ Could not load specific verse \(verse.description)")
            return nil
        }
        
        print("✅ Successfully loaded specific verse \(verse.description) from Bible data")
        return verseData.text
    }
    
    private func fragmentedPageView(_ fragmentedPage: FragmentedPage, size: CGSize) -> some View {
        Text(fragmentedPage.content)
            .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
            .padding(.vertical, LayoutMetrics.verticalPagePadding)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .clipped()
            .onTapGesture { location in
                handleFragmentedVerseTap(location: location, fragmentedPage: fragmentedPage, size: size)
            }
            .background(
                GeometryReader { textGeo in
                    Color.clear
                        .onAppear {
                            let actualContentHeight = textGeo.size.height
                            let availableHeight = size.height
                            print("📏 FRAGMENT VERIFICATION: content=\(actualContentHeight) vs available=\(availableHeight)")
                            print("📊 FRAGMENT STATS: \(fragmentedPage.debugDescription)")
                            
                            // Log fragment details
                            for (index, fragment) in fragmentedPage.fragments.enumerated() {
                                let continuationStatus = fragment.isContinuation ? "↪️" : "🆕"
                                let completionStatus = fragment.hasMoreContent ? "➡️" : "✅"
                                print("   Fragment \(index + 1): \(continuationStatus) \(fragment.reference.book) \(fragment.reference.chapter):\(fragment.reference.verse) \(completionStatus)")
                            }
                            
                            // Fragment-based approach should have better fit
                            if actualContentHeight > availableHeight + 10 { // Small tolerance
                                print("⚠️ FRAGMENT OVERFLOW: Content is \(actualContentHeight - availableHeight)pts too tall")
                                print("📝 Fragment system may need height measurement refinement")
                            } else {
                                print("✅ FRAGMENT SUCCESS: \(fragmentedPage.fragments.count) fragments fit perfectly")
                                print("📏 VERIFIED: \(fragmentedPage.uniqueVerses.count) unique verses across fragments")
                            }
                        }
                        .onChange(of: textGeo.size.height) { _, newHeight in
                            print("📏 FRAGMENT CONTENT HEIGHT CHANGED: \(newHeight)")
                        }
                }
            )
#if DEBUG
            .overlay(alignment: .bottom) { 
                Color.green.frame(height: 4) // Green to distinguish from legacy pages
            }
#endif
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < -50 {
                            Task { await generator.goToNextPage() }
                        } else if value.translation.width > 50 {
                            Task { await generator.goToPreviousPage() }
                        }
                    }
            )
    }
    
    /// Handles tap on fragmented page text to show summary for the tapped verse
    private func handleFragmentedVerseTap(location: CGPoint, fragmentedPage: FragmentedPage, size: CGSize) {
        // Find the verse that was tapped based on location
        guard let tappedVerse = findVerseInFragmentedPage(location: location, fragmentedPage: fragmentedPage, size: size) else {
            print("⚠️ No verse found at tap location in fragmented page")
            return
        }
        
        // Get the verse text from the fragmented page content
        Task {
            let verseText = await extractVerseTextFromFragments(for: tappedVerse, from: fragmentedPage)
            
            // Create a complete verse string that includes both reference and text
            // This format matches what the VerseSummaryViewModel.parseVerse function expects
            let completeVerseString = "\(tappedVerse.description) \(verseText)"
            
            print("🎯 Tapped verse in fragmented page: \(tappedVerse.description)")
            print("📝 Complete verse string: '\(completeVerseString.prefix(100))...'")
            print("📝 Extracted text length: \(verseText.count) characters")
            
            // TODO: Show verse summary popup
            // For now, just log the extracted verse
            print("📖 Fragment verse text: '\(verseText.prefix(100))...'")
        }
    }
    
    /// Finds the verse at the given tap location in a fragmented page
    private func findVerseInFragmentedPage(location: CGPoint, fragmentedPage: FragmentedPage, size: CGSize) -> VerseKey? {
        // Calculate which verse was tapped based on vertical position
        let tapY = location.y
        let pageHeight = size.height
        let uniqueVerses = fragmentedPage.uniqueVerses
        
        if uniqueVerses.isEmpty { return nil }
        
        // Calculate verse height and find which verse was tapped
        let verseHeight = pageHeight / CGFloat(uniqueVerses.count)
        let verseIndex = Int(tapY / verseHeight)
        
        // Ensure index is within bounds
        let clampedIndex = max(0, min(verseIndex, uniqueVerses.count - 1))
        let tappedVerseRef = uniqueVerses[clampedIndex]
        
        // Convert VerseReference to VerseKey
        let tappedVerse = VerseKey(
            book: tappedVerseRef.book,
            chapter: tappedVerseRef.chapter,
            verse: tappedVerseRef.verse
        )
        
        print("📍 Fragment tap at Y: \(tapY), page height: \(pageHeight), unique verses: \(uniqueVerses.count)")
        print("🎯 Calculated verse index: \(clampedIndex), selected: \(tappedVerse.description)")
        
        return tappedVerse
    }
    
    /// Extracts the text for a specific verse from fragmented page content
    private func extractVerseTextFromFragments(for verse: VerseKey, from fragmentedPage: FragmentedPage) async -> String {
        // Look for fragments that contain this verse
        let relevantFragments = fragmentedPage.fragments.filter { fragment in
            fragment.reference.book == verse.book &&
            fragment.reference.chapter == verse.chapter &&
            fragment.reference.verse == verse.verse
        }
        
        if !relevantFragments.isEmpty {
            // Combine all fragments for this verse
            let verseText = relevantFragments.map { $0.textFragment }.joined(separator: " ")
            print("✅ Found verse \(verse.description) in \(relevantFragments.count) fragments")
            return verseText
        }
        
        // Fallback: try to extract from the full content
        return await extractVerseText(for: verse, from: String(fragmentedPage.content.characters))
    }
}

