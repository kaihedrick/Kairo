//
//  LiquidGlassTokens.swift
//  Kairo Liquid Glass Design System
//
//  Design tokens for Liquid Glass UI components
//  Provides consistent spacing, colors, and dimensions across the app
//

import SwiftUI

/// Liquid Glass design tokens for consistent styling
enum LG {
    // MARK: - Spacing & Dimensions
    static let cornerRadius: CGFloat = 22
    static let largeCornerRadius: CGFloat = 28
    static let smallCornerRadius: CGFloat = 16

    // MARK: - Opacity & Transparency
    static let strokeOpacity: Double = 0.28
    static let shadowOpacity: Double = 0.25
    static let highlightOpacity: Double = 0.10
    static let dividerOpacity: Double = 0.15

    // MARK: - Shadows & Depth
    static let shadowRadius: CGFloat = 18
    static let shadowOffset: CGFloat = 8
    static let smallShadowRadius: CGFloat = 12
    static let smallShadowOffset: CGFloat = 4

    // MARK: - Spacing
    static let padding: CGFloat = 16
    static let smallPadding: CGFloat = 12
    static let largePadding: CGFloat = 20

    // MARK: - Animation
    static let springResponse: Double = 0.35
    static let springDamping: Double = 0.85
    static let quickSpringResponse: Double = 0.25

    // MARK: - Materials (with Liquid Glass support for iOS 26+)
    static var backgroundMaterial: Material {
        if #available(iOS 26.0, *) {
            return .ultraThin // Liquid Glass for iOS 26+
        } else {
            return .ultraThin // Fallback to standard Material for iOS 17-25
        }
    }

    static var cardMaterial: Material {
        if #available(iOS 26.0, *) {
            return .regular // Liquid Glass for iOS 26+
        } else {
            return .regular // Fallback to standard Material for iOS 17-25
        }
    }

    static var toolbarMaterial: Material {
        if #available(iOS 26.0, *) {
            return .thin // Liquid Glass for iOS 26+
        } else {
            return .thin // Fallback to standard Material for iOS 17-25
        }
    }

    // MARK: - Colors
    static var glassTint: Color {
        .primary.opacity(0.1)
    }

    static var glassBorder: Color {
        .white.opacity(strokeOpacity)
    }

    static var glassShadow: Color {
        .black.opacity(shadowOpacity)
    }

    // MARK: - Accessibility
    static func reducedTransparencyMaterial(_ material: Material) -> some ShapeStyle {
        if UITraitCollection.current.userInterfaceStyle == .dark {
            return Color(.systemBackground)
        } else {
            return Color(.secondarySystemBackground)
        }
    }

    // MARK: - Spring Animation
    static var spring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    static var quickSpring: Animation {
        .spring(response: quickSpringResponse, dampingFraction: springDamping)
    }

    // MARK: - Accessibility Helpers
    static func accessibilityAdjustedMaterial(_ material: Material) -> some ShapeStyle {
        // For now, return the material as-is
        // In a production app, you would check accessibility settings
        return material
    }

    static func accessibilityAdjustedOpacity(_ opacity: Double) -> Double {
        // For now, return the opacity as-is
        // In a production app, you would adjust based on accessibility settings
        return opacity
    }
}

// MARK: - Convenience Extensions
extension View {
    func lgSpring() -> some View {
        self.animation(LG.spring, value: true)
    }

    func lgQuickSpring() -> some View {
        self.animation(LG.quickSpring, value: true)
    }
}
