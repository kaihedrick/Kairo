//
//  LiquidGlassStyles.swift
//  Kairo Liquid Glass Design System
//
//  Reusable modifiers, styles, and components for Liquid Glass UI
//

import SwiftUI

// MARK: - Glass Card Component
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var material: Material = LG.cardMaterial

    var body: some View {
        content
            .padding(LG.padding)
            .background(material, in: RoundedRectangle(cornerRadius: LG.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LG.cornerRadius, style: .continuous)
                    .stroke(LG.glassBorder, lineWidth: 1)
                    .allowsHitTesting(false) // Decorative border - don't block taps
            )
            .shadow(color: LG.glassShadow, radius: LG.shadowRadius, y: LG.shadowOffset)
            .overlay(
                // Soft specular highlight
                RoundedRectangle(cornerRadius: LG.cornerRadius, style: .continuous)
                    .fill(LinearGradient(stops: [
                        .init(color: .white.opacity(LG.highlightOpacity), location: 0.0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .white.opacity(0.06), location: 0.6),
                        .init(color: .clear, location: 1.0)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false) // Decorative highlight - don't block taps
            )
    }
}

// MARK: - Glass Toolbar Extension
extension View {
    func glassToolbar() -> some View {
        self
            .toolbarBackground(LG.toolbarMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Glass Button Style
struct GlassButtonStyle: ButtonStyle {
    var material: Material = LG.cardMaterial

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(material, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(LG.glassBorder)
                    .allowsHitTesting(false) // Decorative border - don't block taps
            )
            .shadow(color: LG.glassShadow, radius: LG.smallShadowRadius, y: LG.smallShadowOffset)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .lgSpring()
    }
}

// MARK: - Glass Sheet (Verse Summary)
struct VerseSummarySheet<Content: View>: View {
    @ViewBuilder var content: Content
    var material: Material = LG.backgroundMaterial

    var body: some View {
        VStack(spacing: 0) {
            // Handle indicator
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(width: 44, height: 5)
                .padding(.top, 8)

            content
                .padding(LG.padding)
        }
        .background(material)
        .clipShape(RoundedRectangle(cornerRadius: LG.largeCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 20)
    }
}

// MARK: - Glass Background Modifier
extension View {
    func glassBackground() -> some View {
        self
            .background(LG.backgroundMaterial)
    }
}

// MARK: - Glass Chip Style
struct GlassChip: View {
    var text: String
    var material: Material = LG.cardMaterial

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(material, in: Capsule())
            .overlay(Capsule().stroke(LG.glassBorder.opacity(0.5)))
            .shadow(color: LG.glassShadow.opacity(0.5), radius: LG.smallShadowRadius/2, y: LG.smallShadowOffset/2)
    }
}

// MARK: - Glass Divider
struct GlassDivider: View {
    var opacity: Double = LG.dividerOpacity

    var body: some View {
        Rectangle()
            .fill(.white.opacity(opacity))
            .frame(height: 1)
            .padding(.horizontal, LG.padding)
    }
}

// MARK: - Glass Toast/Snackbar
struct GlassToast: View {
    var message: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let image = systemImage {
                Image(systemName: image)
                    .foregroundStyle(.secondary)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .padding(LG.smallPadding)
        .background(LG.cardMaterial, in: RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous)
                .stroke(LG.glassBorder.opacity(0.5), lineWidth: 1)
                .allowsHitTesting(false) // Decorative border - don't block taps
        )
        .shadow(color: LG.glassShadow, radius: LG.smallShadowRadius, y: LG.smallShadowOffset)
        .padding(.horizontal, LG.padding)
    }
}

// MARK: - Glass Verse Row (for Bible Reader)
struct GlassVerseRow<Content: View>: View {
    @ViewBuilder var content: Content
    var isSelected: Bool = false
    var material: Material = LG.backgroundMaterial

    var body: some View {
        content
            .padding(LG.smallPadding)
            .background(
                material.opacity(isSelected ? 0.8 : 0.4),
                in: RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous)
                    .stroke(isSelected ? LG.glassBorder.opacity(0.8) : LG.glassBorder.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    .allowsHitTesting(false) // Decorative border - don't block taps
            )
            .shadow(color: LG.glassShadow.opacity(isSelected ? 0.3 : 0.1), radius: isSelected ? LG.smallShadowRadius : LG.smallShadowRadius/2, y: isSelected ? LG.smallShadowOffset : LG.smallShadowOffset/2)
            .lgSpring()
    }
}

// MARK: - Glass Navigation Link Style
// ⚠️ WARNING: Do NOT use this ButtonStyle with NavigationLink!
// It can break tap detection. Instead, style the NavigationLink label directly.
// Use .buttonStyle(.plain) with NavigationLink for reliable tap behavior.
struct GlassNavigationLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(LG.smallPadding)
            .background(LG.cardMaterial.opacity(configuration.isPressed ? 0.8 : 0.6), in: RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous)
                    .stroke(LG.glassBorder.opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false) // Decorative border - don't block taps
            )
            .shadow(color: LG.glassShadow.opacity(0.3), radius: LG.smallShadowRadius, y: LG.smallShadowOffset)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .lgSpring()
    }
}

// MARK: - Convenience Button Style Extension
extension Button {
    func glassButtonStyle() -> some View {
        self.buttonStyle(GlassButtonStyle())
    }
}

// MARK: - Hit-Testing Helpers for Glass Components
extension View {
    /// Applies glass styling to a view while ensuring proper hit-testing
    func glassStyled() -> some View {
        self
            .background(LG.cardMaterial, in: RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous)
                    .stroke(LG.glassBorder.opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false) // Decorative - don't block taps
            )
            .shadow(color: LG.glassShadow.opacity(0.3), radius: LG.smallShadowRadius, y: LG.smallShadowOffset)
    }

    /// Adds decorative glass overlay that doesn't interfere with taps
    func glassOverlay(shape: some Shape = RoundedRectangle(cornerRadius: 12, style: .continuous)) -> some View {
        self.overlay(
            shape
                .stroke(LG.glassBorder.opacity(0.3), lineWidth: 1)
                .allowsHitTesting(false) // Purely decorative
        )
    }

    /// Adds glass highlight that doesn't block taps
    func glassHighlight(shape: some Shape = RoundedRectangle(cornerRadius: 12, style: .continuous)) -> some View {
        self.overlay(
            shape
                .fill(LinearGradient(
                    colors: [.white.opacity(0.1), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .allowsHitTesting(false) // Purely decorative highlight
        )
    }

    /// Ensures proper content shape for tappable glass elements
    func glassTappable(shape: some Shape = RoundedRectangle(cornerRadius: 12, style: .continuous)) -> some View {
        self
            .contentShape(shape)
            .allowsHitTesting(true) // Ensure this element is tappable
    }
}

// MARK: - NavigationLink Glass Styling (Safe)
extension View {
    /// Safe way to style NavigationLink labels with glass effects
    /// This styles the label directly instead of using ButtonStyle
    func glassNavigationLabel() -> some View {
        self
            .padding(LG.smallPadding)
            .background(LG.cardMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous)
                    .stroke(LG.glassBorder.opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false) // Decorative - don't interfere with NavigationLink
            )
            .shadow(color: LG.glassShadow.opacity(0.3), radius: LG.smallShadowRadius, y: LG.smallShadowOffset)
            .contentShape(RoundedRectangle(cornerRadius: LG.smallCornerRadius, style: .continuous))
    }
}

// MARK: - Accessibility Helpers (defined in LiquidGlassTokens.swift)
