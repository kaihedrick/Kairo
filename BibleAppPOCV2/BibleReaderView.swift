// filepath: BibleAppPOCV2/BibleReaderView.swift
// filepath: BibleAppPOCV2/BibleReaderView.swift
import SwiftUI

struct BibleReaderView: View {
    @State private var selectedVerse: String? = nil
    @StateObject private var summaryViewModel = VerseSummaryViewModel()
    
    var body: some View {
        VStack {
            // ... your Bible reading UI ...
            Button("Summarize Selected Verse") {
                selectedVerse = "In the beginning God created the heaven and the earth."
            }
        }
        .sheet(item: $selectedVerse) { verse in
            VerseSummaryPopupView(viewModel: summaryViewModel, verse: verse)
        }
    }
}

// For preview/demo
struct BibleReaderView_Previews: PreviewProvider {
    static var previews: some View {
        BibleReaderView()
    }
}
