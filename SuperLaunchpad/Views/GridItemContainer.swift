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
    @Environment(\.enterEditMode) private var enterEditMode

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
            .editModeGestures(enterEditMode)
        }
    }
}

extension EnvironmentValues {
    // True while an icon is being dragged on the main grid.
    @Entry var isGridDragActive = false
    // Edit mode: icons wiggle (see `WiggleEffect`).
    @Entry var isEditing = false
    @Entry var enterEditMode = EnterEditModeAction(viewModel: nil)
}

// What a long press on an icon does. Compared by view model identity, so a
// launcher re-render doesn't hand every icon a "changed" environment value
// the way a fresh closure would.
struct EnterEditModeAction: Equatable {
    let viewModel: LaunchpadViewModel?

    @MainActor func callAsFunction() {
        viewModel?.enterEditMode()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel === rhs.viewModel
    }
}

extension View {
    // Long press to enter edit mode, plus the wiggle while in it. Shared by
    // grid icons and the open folder's icons.
    func editModeGestures(_ enterEditMode: EnterEditModeAction) -> some View {
        modifier(WiggleEffect())
            .onLongPressGesture(minimumDuration: Edit.longPressDuration, maximumDistance: Drag.threshold) {
                enterEditMode()
            }
    }
}

// Rocks the icon while in edit mode. Each icon reads the shared clock
// (`TimelineView`'s date) inside its own small closure, so a frame only
// re-renders the rotation, never the icon or the grid around it. Paused
// outside edit mode. The view tree is the same in and out of edit mode, so
// entering it doesn't reset hover state.
private struct WiggleEffect: ViewModifier {
    @Environment(\.isEditing) private var isEditing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Random start in the cycle, so neighbours don't rock in lockstep.
    @State private var phase = Double.random(in: 0..<1)

    func body(content: Content) -> some View {
        let wiggles = isEditing && !reduceMotion
        TimelineView(.animation(paused: !wiggles)) { context in
            content
                .rotationEffect(.degrees(wiggles ? angle(at: context.date) : 0))
        }
        // Reduce Motion: a still cue instead of the rocking.
        .scaleEffect(isEditing && reduceMotion ? Edit.reducedMotionScale : 1)
        .animation(.easeInOut(duration: Edit.reducedMotionAnimation), value: isEditing && reduceMotion)
    }

    private func angle(at date: Date) -> Double {
        let cycle = date.timeIntervalSinceReferenceDate / Edit.wigglePeriod + phase
        return sin(cycle * 2 * .pi) * Edit.wiggleAngle
    }
}
