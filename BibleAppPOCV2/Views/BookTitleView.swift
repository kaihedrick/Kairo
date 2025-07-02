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
        VStack(spacing: 4) {
            Text(abbreviation)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(fullName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
