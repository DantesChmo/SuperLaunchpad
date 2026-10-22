import SwiftUI

/// Inner container for grid items.
/// Hover is on an explicit inner box (icon + label) with known dimensions.
///
/// Generic over two view types — same pattern as SwiftUI's own `Button(_:label:)`.
/// `Icon` and `Label` get inferred from whatever the caller passes into the
/// two `@ViewBuilder` closures.
///
/// Why two nested VStacks? The outer one expands to fill whatever cell size
/// the parent gives (so each cell of the LazyVGrid stays uniform). The inner
/// one has an EXPLICIT size — hover/tap modifiers only fire on this inner
/// hit-box, so empty cell space around the icon doesn't trigger hover scaling.
/// Without this, hovering an empty corner of a cell would scale the icon.
struct GridItemContainer<Icon: View, Label: View>: View {
    let metrics: LayoutMetrics
    let onTap: () -> Void
    @ViewBuilder let icon: Icon
    @ViewBuilder let label: Label

    @State private var isHovering = false
    @Environment(\.isGridDragActive) private var isGridDragActive

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: LayoutMetrics.iconLabelSpacing) {
                icon
                label
            }
            // Explicit inner frame = predictable hover/tap target.
            // Height = icon + spacing + room for up to 2 label lines.
            .frame(width: metrics.itemHitSize.width, height: metrics.itemHitSize.height)
            // 1.08× scale on hover — matches macOS Launchpad's subtle bump.
            // Icons sliding under a dragged one are not hovered.
            .scaleEffect(isHovering && !isGridDragActive ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering && !isGridDragActive)
            // `onHover` is macOS-only (iOS has no cursor). Fires `true` on
            // mouse enter and `false` on exit.
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                onTap()
            }
        }
    }
}

extension EnvironmentValues {
    // True while an icon is being dragged on the main grid.
    @Entry var isGridDragActive = false
}
