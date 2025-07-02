//
//  GlassModifier.swift
//  AIStudyBiblePOC
//
//  Created by Jeff Hedrick on 6/10/25.
//

import SwiftUI

extension View {
    func glassBackground(cornerRadius: CGFloat = 20, blurRadius: CGFloat = 0) -> some View {
        self
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}
