#if os(macOS)
import SwiftUI
import AppKit

// MARK: - AppTheme
//
// Centralised semantic colour palette.  Every view should reference these
// instead of hard-coded hex values so light/dark mode adaptation is automatic.
//
// Usage:
//   .foregroundStyle(AppTheme.secondaryLabel)
//   .background(AppTheme.secondaryBackground)

enum AppTheme {

    // MARK: Labels (text)

    /// Primary text — NSColor.labelColor
    static var primaryLabel: Color    { Color(NSColor.labelColor) }
    /// Secondary text — NSColor.secondaryLabelColor
    static var secondaryLabel: Color  { Color(NSColor.secondaryLabelColor) }
    /// Tertiary text — NSColor.tertiaryLabelColor
    static var tertiaryLabel: Color   { Color(NSColor.tertiaryLabelColor) }

    // MARK: Backgrounds

    /// Main window background — NSColor.windowBackgroundColor
    static var windowBackground: Color    { Color(NSColor.windowBackgroundColor) }
    /// Secondary surfaces (toolbars, strips) — NSColor.controlBackgroundColor
    static var secondaryBackground: Color { Color(NSColor.controlBackgroundColor) }
    /// Tertiary surface (inline code, hover state) — NSColor.secondarySystemFill
    static var tertiaryBackground: Color  { Color(NSColor.secondarySystemFill) }

    // MARK: Separators

    static var separator: Color { Color(NSColor.separatorColor) }

    // MARK: Accent

    /// System accent colour (follows user preference)
    static var accent: Color { Color.accentColor }

    // MARK: Annotation defaults

    /// Default red used for arrows and rects
    static var annotationRed:    NSColor { NSColor(hex: "#FF3B30") ?? .systemRed }
    /// Default yellow for highlights
    static var annotationYellow: NSColor { NSColor(hex: "#FFD60A") ?? .systemYellow }

    // MARK: Tag chip

    static func tagForeground(selected: Bool) -> Color {
        selected ? .white : .accentColor
    }
    static func tagBackground(selected: Bool) -> Color {
        selected ? .accentColor : .accentColor.opacity(0.12)
    }

    // MARK: - NSFont helpers

    static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
    static func monoFont(size: CGFloat = 13) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

// MARK: - View helpers

extension View {
    /// Applies a standard card-style background with rounded corners and a
    /// separator-coloured border.  Useful for panels and list row highlights.
    func cardBackground(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(AppTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(AppTheme.separator, lineWidth: 0.5)
            )
    }
}
#endif
