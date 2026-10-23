import SwiftUI

// How the arrow-key focus ring is drawn: a white outline on a thin dark edge,
// wider and fully opaque with Increase Contrast.
struct KeyboardFocusRingStyle: Equatable {
    let lineWidth: CGFloat
    let opacity: Double
    let edgeWidth: CGFloat
    let edgeOpacity: Double

    init(increasedContrast: Bool) {
        lineWidth = increasedContrast ? KeyboardFocus.increasedLineWidth : KeyboardFocus.lineWidth
        opacity = increasedContrast ? 1 : KeyboardFocus.opacity
        edgeWidth = KeyboardFocus.edgeWidth
        edgeOpacity = increasedContrast ? KeyboardFocus.increasedEdgeOpacity : KeyboardFocus.edgeOpacity
    }
}

extension View {
    // The ring around a focused icon and its label, the same box as the
    // search highlight. Purely visual: VoiceOver's own cursor is separate,
    // and the ring changes no trait (`.isSelected` belongs to multi-select).
    func keyboardFocusRing(_ isFocused: Bool, iconSize: CGFloat) -> some View {
        modifier(KeyboardFocusRingModifier(isFocused: isFocused, iconSize: iconSize))
    }
}

private struct KeyboardFocusRingModifier: ViewModifier {
    let isFocused: Bool
    let iconSize: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isFocused {
                    ring
                        .padding(-iconSize * Search.selectionOutsetRatio)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity.combined(with: .scale(scale: Motion(reduced: reduceMotion).focusRingAppearScale)))
                }
            }
            .animation(.easeOut(duration: KeyboardFocus.ringAnimation), value: isFocused)
    }

    private var ring: some View {
        let style = KeyboardFocusRingStyle(increasedContrast: contrast == .increased)
        let shape = RoundedRectangle(cornerRadius: Search.selectionCornerRadius)
        return shape
            .strokeBorder(.black.opacity(style.edgeOpacity), lineWidth: style.lineWidth + style.edgeWidth * 2)
            .overlay {
                shape
                    .inset(by: style.edgeWidth)
                    .strokeBorder(.white.opacity(style.opacity), lineWidth: style.lineWidth)
            }
    }
}
