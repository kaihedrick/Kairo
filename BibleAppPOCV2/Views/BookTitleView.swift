//
//  BookTitleView.swift
//  AIStudyBiblePOC
//
//  Created by Jeff Hedrick on 6/10/25.
//

import SwiftUI

struct BookTileView: View {
    let abbreviation: String
    let fullName: String

    var body: some View {
        VStack(spacing: 3) {  // Reduced spacing for smaller tiles
            Text(abbreviation)
                .font(.footnote.weight(.semibold))  // Reduced from .title3 to .footnote
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)  // Allow scaling if needed
            
            Text(fullName)
                .font(.caption2)  // Reduced from .caption to .caption2
                .foregroundColor(.secondary)
                .lineLimit(1)  // Reduced from 2 lines to 1 for consistency
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)  // Reduced padding from 10 to 6 for smaller tiles
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))  // Reduced corner radius from 12 to 8
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)  // Reduced shadow for smaller tiles
    }
}
