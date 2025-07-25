// filepath: BibleAppPOCV2/VerseSummaryPopupView.swift
import SwiftUI

struct VerseSummaryPopupView: View {
    @ObservedObject var viewModel: VerseSummaryViewModel
    let verse: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Verse Summary")
                .font(.title2)
                .fontWeight(.bold)
            Text(verse)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else {
                Text(viewModel.summary)
                    .font(.body)
                    .padding()
            }
            Button("Close") {
                // Dismiss handled by parent
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            viewModel.summarizeVerse(verse)
        }
    }
}
