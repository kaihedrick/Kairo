// filepath: BibleAppPOCV2/Views/VerseButtonView.swift
// VerseButtonView.swift
// Per-verse button view for exact tapping

import SwiftUI
import Foundation

/// Per-verse button view for exact tapping
struct VerseButtonView: View {
    let attributed: AttributedString
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            // Preserve paragraph look
            Text(attributed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .lineSpacing(Typography.lineSpacing)
                .textSelection(.enabled)
        }
        .buttonStyle(.plain) // No button chrome
        .contentShape(Rectangle())
        .padding(.zero)
    }
}
