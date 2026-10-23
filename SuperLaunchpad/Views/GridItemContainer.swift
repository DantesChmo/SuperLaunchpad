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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: LayoutMetrics.iconLabelSpacing) {
                icon
                // Settings → Appearance → Hide labels. The accessibility
                // label is set by the cell, so VoiceOver keeps the name.
                if metrics.showsLabels {
                    label
                }
            }
            // Explicit inner frame = predictable hover/tap target.
            // Height = icon + spacing + room for up to 2 label lines.
            .frame(width: metrics.itemHitSize.width, height: metrics.itemHitSize.height)
            // 1.08× scale on hover — matches macOS Launchpad's subtle bump
            // (none with Reduce Motion). Icons sliding under a dragged one
            // are not hovered.
            .scaleEffect(Motion(reduced: reduceMotion).hoverScale(isHovering: isHovering && !isGridDragActive))
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
    // Apps checked in edit mode (`EditingModel.selection`).
    @Entry var selectedAppIDs: Set<String> = []
    @Entry var enterEditMode = EnterEditModeAction(viewModel: nil)
    @Entry var removeApp = RemoveAppAction(viewModel: nil)
}

// What the × on an app in edit mode does. Compared by view model identity,
// like `EnterEditModeAction`.
struct RemoveAppAction: Equatable {
    let viewModel: LaunchpadViewModel?

    @MainActor func callAsFunction(_ app: AppEntry) {
        viewModel?.removal.requestRemoval(of: app)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel === rhs.viewModel
    }
}

// What a long press on an icon does. Compared by view model identity, so a
// launcher re-render doesn't hand every icon a "changed" environment value
// the way a fresh closure would.
struct EnterEditModeAction: Equatable {
    let viewModel: LaunchpadViewModel?

    @MainActor func callAsFunction() {
        viewModel?.editing.enterEditMode()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel === rhs.viewModel
    }
}

extension View {
    // One VoiceOver element per icon (see `LauncherItemAccessibility`).
    func launcherItemAccessibility(label: String, hint: String, onActivate: @escaping () -> Void) -> some View {
        modifier(LauncherItemAccessibility(label: label, hint: hint, onActivate: onActivate))
    }

    // Icon labels sit straight on the blurred desktop: a soft shadow keeps
    // them readable over a bright wallpaper, as in the system Launchpad.
    func launcherLabelShadow() -> some View {
        shadow(
            color: .black.opacity(LabelContrast.shadowOpacity),
            radius: LabelContrast.shadowRadius,
            y: LabelContrast.shadowOffset
        )
    }

    // "New" for an app that has the blue dot (or a folder holding one).
    func newAppAccessibilityValue(_ isNew: Bool) -> some View {
        accessibilityValue(isNew ? Text("New") : Text(""))
    }

    // The × on an app icon in edit mode. Apps that are part of macOS have none.
    func removeAppBadge(_ app: AppEntry, iconSize: CGFloat) -> some View {
        modifier(RemoveAppBadge(app: app, iconSize: iconSize))
    }

    // The hide button on an app icon's top-right corner in edit mode.
    func hideAppBadge(_ app: AppEntry, iconSize: CGFloat) -> some View {
        modifier(HideAppBadge(app: app, iconSize: iconSize))
    }

    // The checkmark on a selected app's icon in edit mode.
    func selectionCheckmark(_ app: AppEntry, iconSize: CGFloat) -> some View {
        modifier(SelectionCheckmark(app: app, iconSize: iconSize))
    }

    // The selected trait for VoiceOver on an app's element while it is checked.
    func selectionAccessibility(_ app: AppEntry) -> some View {
        modifier(SelectionAccessibility(app: app))
    }

    // The Dock's dot under the icon of a running app, in the gap above the label.
    func runningDot(_ app: AppEntry) -> some View {
        modifier(RunningDot(app: app))
    }

    // Long press to enter edit mode, plus the wiggle while in it. Shared by
    // grid icons and the open folder's icons.
    func editModeGestures(_ enterEditMode: EnterEditModeAction) -> some View {
        modifier(WiggleEffect())
            .onLongPressGesture(minimumDuration: Edit.longPressDuration, maximumDistance: Drag.threshold) {
                enterEditMode()
            }
    }
}

// Icon, name and backplate read as one element: the name, a hint and the
// click as the default action. The context menu adds the other actions (see
// `ItemContextMenu`), Edit Layout among them, standing in for the long press,
// which VoiceOver can't perform.
private struct LauncherItemAccessibility: ViewModifier {
    let label: String
    let hint: String
    let onActivate: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAction {
                onActivate()
            }
    }
}

private struct RunningDot: ViewModifier {
    let app: AppEntry

    @Environment(\.runningApps) private var runningApps

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if runningApps?.isRunning(app) == true {
                    Circle()
                        .fill(.white.opacity(RunningIndicator.opacity))
                        .frame(width: RunningIndicator.size, height: RunningIndicator.size)
                        .offset(y: (LayoutMetrics.iconLabelSpacing + RunningIndicator.size) / 2)
                        .launcherLabelShadow()
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct RemoveAppBadge: ViewModifier {
    let app: AppEntry
    let iconSize: CGFloat

    @Environment(\.isEditing) private var isEditing
    @Environment(\.removeApp) private var removeApp

    func body(content: Content) -> some View {
        // Checked only in edit mode: it resolves the path on disk.
        let removable = isEditing && AppTrash.isRemovable(appPath: app.appPath)
        content
            .overlay(alignment: .topLeading) {
                if removable {
                    badge
                }
            }
    }

    private var badge: some View {
        EditBadge(systemImage: "xmark", iconSize: iconSize, isLeading: true) {
            removeApp(app)
        }
        .accessibilityIdentifier("remove-app-badge")
    }
}

private struct HideAppBadge: ViewModifier {
    let app: AppEntry
    let iconSize: CGFloat

    @Environment(\.isEditing) private var isEditing
    @Environment(\.itemMenu) private var itemMenu

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isEditing {
                    EditBadge(systemImage: "eye.slash", iconSize: iconSize, isLeading: false) {
                        itemMenu.perform(.hide, on: app)
                    }
                    .accessibilityIdentifier("hide-app-badge")
                }
            }
    }
}

private struct SelectionCheckmark: ViewModifier {
    let app: AppEntry
    let iconSize: CGFloat

    @Environment(\.isEditing) private var isEditing
    @Environment(\.selectedAppIDs) private var selectedAppIDs

    func body(content: Content) -> some View {
        let isSelected = isEditing && selectedAppIDs.contains(app.id)
        let size = iconSize * Selection.checkmarkSizeRatio
        let outset = size * Selection.checkmarkOutset
        content
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .frame(width: size, height: size)
                        .launcherLabelShadow()
                        .offset(x: outset, y: outset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("selection-checkmark")
                }
            }
    }
}

private struct SelectionAccessibility: ViewModifier {
    let app: AppEntry

    @Environment(\.isEditing) private var isEditing
    @Environment(\.selectedAppIDs) private var selectedAppIDs

    func body(content: Content) -> some View {
        let isSelected = isEditing && selectedAppIDs.contains(app.id)
        // A trait, not a value: the value already says "New".
        content
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// A round button sticking out past one of the icon's top corners.
private struct EditBadge: View {
    let systemImage: String
    let iconSize: CGFloat
    let isLeading: Bool
    let action: () -> Void

    var body: some View {
        let size = iconSize * Uninstall.badgeSizeRatio
        let outset = size * Uninstall.badgeOutset
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * Uninstall.badgeGlyphRatio, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(Uninstall.badgeOpacity)))
                .launcherLabelShadow()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: isLeading ? -outset : outset, y: -outset)
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
        let motion = Motion(reduced: reduceMotion)
        let wiggles = motion.wiggles(isEditing: isEditing)
        TimelineView(.animation(paused: !wiggles)) { context in
            content
                .rotationEffect(.degrees(wiggles ? angle(at: context.date) : 0))
        }
        // Reduce Motion: a still cue instead of the rocking.
        .scaleEffect(motion.editScale(isEditing: isEditing))
        .animation(.easeInOut(duration: Edit.reducedMotionAnimation), value: isEditing && reduceMotion)
    }

    private func angle(at date: Date) -> Double {
        let cycle = date.timeIntervalSinceReferenceDate / Edit.wigglePeriod + phase
        return sin(cycle * 2 * .pi) * Edit.wiggleAngle
    }
}

extension Text {
    // An icon's name, after a blue dot when the app is new, as in the system
    // Launchpad. Part of the text, so it wraps and centers with the name.
    static func launcherLabel(_ title: String, isNew: Bool, fontSize: CGFloat) -> Text {
        let name = Text(title).font(.system(size: fontSize))
        guard isNew else { return name }
        let dotSize = fontSize * NewAppDot.sizeRatio
        let dot = Text(Image(systemName: "circle.fill"))
            .font(.system(size: dotSize))
            .foregroundStyle(.blue)
            .baselineOffset((fontSize - dotSize) * NewAppDot.capMiddleRatio)
        return Text("\(dot) \(name)")
    }
}
