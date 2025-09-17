// filepath: BibleAppPOCV2/Views/VerseSummaryPopupView.swift
import SwiftUI

struct VerseSummaryPopupView: View {
    @Environment(\.presentationMode) var presentationMode
    let summary: VerseSummary
    let onClose: () -> Void
    @StateObject private var viewModel: VerseSummaryViewModel

    init(summary: VerseSummary, onClose: @escaping () -> Void) {
        self.summary = summary
        self.onClose = onClose
        // Shared instance preserves readiness state across popups
        self._viewModel = StateObject(wrappedValue: VerseSummaryViewModel.shared)
    }

    var body: some View {
        VerseSummarySheet {
            VStack(spacing: LG.smallPadding) {
                // Header
                VStack(spacing: LG.smallPadding) {
                    Text("\(summary.reference) Commentary")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    GlassDivider()
                }

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: LG.padding) {
                        if viewModel.isLoading {
                            loadingView(text: "Generating commentary...")
                        } else if !viewModel.modelAvailable {
                            loadingView(text: "Loading database...")
                        } else if !viewModel.errorMessage.isEmpty {
                            errorView(message: viewModel.errorMessage)
                        } else {
                            commentarySection
                            devotionalSection
                            if viewModel.commentaryText.isEmpty &&
                               viewModel.devotionalText.isEmpty {
                                GlassCard {
                                    Text("No commentary available")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                    }
                }

                // Close Button
                Button(action: onClose) {
                    Label("Close", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .padding(.vertical, LG.smallPadding)
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle()
            }
        }
        .transition(.scale.combined(with: .opacity))
        .lgSpring()
        .accessibilityElement(children: .contain)
        .task {
            await viewModel.summarize(verse: summary.summaryText)
        }
    }

    // MARK: - Subviews

    @ViewBuilder private func loadingView(text: String) -> some View {
        GlassCard {
            HStack {
                ProgressView().scaleEffect(0.8)
                Text(text).font(.body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder private func errorView(message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: LG.smallPadding) {
                Label("Error", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button("Retry") { viewModel.retryInitialization() }
                    .glassButtonStyle()
            }
        }
    }

    @ViewBuilder private var commentarySection: some View {
        if !viewModel.commentaryText.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: LG.smallPadding) {
                    Label("Commentary", systemImage: "text.book.closed")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(viewModel.commentaryText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private var devotionalSection: some View {
        if !viewModel.devotionalText.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: LG.smallPadding) {
                    Label("Devotional", systemImage: "heart")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(viewModel.devotionalText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
