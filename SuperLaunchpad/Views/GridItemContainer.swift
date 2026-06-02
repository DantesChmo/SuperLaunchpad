import SwiftUI

/// Inner container for grid items.
/// Hover is on an explicit inner box (icon + label) with known dimensions.
struct GridItemContainer<Icon: View, Label: View>: View {
    let metrics: LayoutMetrics
    let onTap: () -> Void
    @ViewBuilder let icon: Icon
    @ViewBuilder let label: Label

    @State private var isHovering = false

    var body: some View {
        // Outer: no hover, takes whatever size parent gives
        VStack(spacing: 0) {
            // Inner: explicit size, hover lives here
            VStack(spacing: 6) {
                icon
                label
            }
            .frame(width: metrics.iconSize, height: metrics.iconSize + 6 + metrics.labelFont * 3)
            .scaleEffect(isHovering ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                onTap()
            }
        }
    }
}
