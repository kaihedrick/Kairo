import SwiftUI

struct VerseSummaryPopupView: View {
    let verseKey: VerseKey
    @Binding var isVisible: Bool
    @EnvironmentObject var summaryViewModel: VerseSummaryViewModel
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    isVisible = false
                }
            
            VStack(spacing: 16) {
                // Grab Handle
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 40, height: 5)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                // Header with close button
                HStack {
                    Text("\(verseKey.book) \(verseKey.chapter):\(verseKey.verse)")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                    
                    Button(action: { isVisible = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Divider()

                // Content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if summaryViewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView("Loading...")
                                    .padding()
                                Spacer()
                            }
                        } else if let errorMessage = summaryViewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.body)
                                .padding()
                        } else if !summaryViewModel.summaryText.isEmpty {
                            Text(summaryViewModel.summaryText)
                                .font(.body)
                                .padding(.horizontal)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 300)
                
                Divider()
                
                // Close Button
                Button(action: { isVisible = false }) {
                    Text("Close")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding(.top, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(radius: 10)
            .frame(maxWidth: 350, maxHeight: 450)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
        .onAppear {
            Task {
                await summaryViewModel.loadSummary(for: verseKey)
            }
        }
    }
}
