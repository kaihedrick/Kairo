// filepath: BibleAppPOCV2/ViewModifiers/GlassModifier.swift
import SwiftUI

// MARK: - Glass Effect View Modifier

extension View {
    /// Apply glass tile effect with modern iOS 18.5+ compatible APIs
    @ViewBuilder func glassTile(cornerRadius: CGFloat = 12, id: String, namespace: Namespace.ID) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .stroke(.primary.opacity(0.15), lineWidth: 0.5)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
    }
    
    /// Enhanced liquid glass effect for interactive elements (search overlay)
    @ViewBuilder func glassedEffect<S: Shape>(shape: S, interactive: Bool = false) -> some View {
        self.background {
            shape
                .fill(.ultraThinMaterial)
                .stroke(.primary.opacity(interactive ? 0.3 : 0.2), lineWidth: interactive ? 1.0 : 0.7)
                .shadow(color: Color.black.opacity(interactive ? 0.15 : 0.1), radius: interactive ? 12 : 10, x: 0, y: interactive ? 5 : 4)
                .overlay(
                    shape
                        .stroke(.white.opacity(interactive ? 0.2 : 0.1), lineWidth: 0.5)
                        .blur(radius: 0.5)
                )
        }
    }

    /// Safe wrapper for glass effect union - enhanced for liquid animations
    @ViewBuilder func glassEffectUnionSafe(id: String, namespace: Namespace.ID) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    .blur(radius: 1.0)
            )
    }
    
    /// Legacy glass background effect for backwards compatibility
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
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}
