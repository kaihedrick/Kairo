// filepath: BibleAppPOCV2/Views/VerseSummaryPopupView.swift
import SwiftUI

struct VerseSummaryPopupView: View {
    let summary: VerseSummary
    let onClose: () -> Void
    @StateObject private var viewModel: VerseSummaryViewModel
    
    init(summary: VerseSummary, onClose: @escaping () -> Void) {
        self.summary = summary
        self.onClose = onClose
        // Use shared instance to preserve modelAvailable state
        self._viewModel = StateObject(wrappedValue: VerseSummaryViewModel.shared)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Grab Handle
            RoundedRectangle(cornerRadius: 2)
                .frame(width: 40, height: 5)
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            // Header
            Text("\(summary.reference) AI Commentary")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating AI commentary...")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else if !viewModel.modelAvailable {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading Core ML model...")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else if !viewModel.errorMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Error", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                                .foregroundStyle(.red)
                            
                            Text(viewModel.errorMessage)
                                .font(.body)
                                .foregroundStyle(.secondary)
                            
                            Button("Retry") {
                                viewModel.retryInitialization()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(.red.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        // Commentary Section
                        if !viewModel.commentaryText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Commentary", systemImage: "text.book.closed")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                Text(viewModel.commentaryText)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(.blue.opacity(0.05))
                            .cornerRadius(8)
                        }
                        
                        // Devotional Section
                        if !viewModel.devotionalText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Devotional", systemImage: "heart")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                Text(viewModel.devotionalText)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(.green.opacity(0.05))
                            .cornerRadius(8)
                        }
                        
                        // No content message
                        if viewModel.commentaryText.isEmpty && viewModel.devotionalText.isEmpty {
                            Text("No commentary available")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        }
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            // Metadata
            VStack(spacing: 4) {
                if let version = summary.modelVersion {
                    Text("Generated by: \(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(viewModel.modelVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(4)
                
                Text(viewModel.getSummarizerStatus())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Close Button
            Button(action: onClose) {
                Label("Close", systemImage: "xmark.circle.fill")
                    .font(.headline)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding(.top, 4)
        .background(.background)
        .cornerRadius(16)
        .shadow(radius: 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom))
        .accessibilityElement(children: .contain)
        .onAppear {
            viewModel.summarize(verse: summary.summaryText)
        }
    }
}
