import SwiftUI

// The icon drag gesture, on the launcher root. One `DragGesture` for the main
// grid and the open folder: attached here, it survives the folder popup
// closing when a dragged app leaves it. Taps on icons still work because the
// gesture is simultaneous and starts only after `Drag.threshold`.
//
// Also draws the lifted icon above everything (folder popup included) and
// ends the drag when the launcher hides, a search starts, or Esc is pressed.
// In edit mode it lifts the whole selection with a selected app, and a press
// outside any icon draws a marquee that selects (see AGENTS.md →
// "Multi-select").
struct LaunchpadDragGesture: ViewModifier {
    let viewModel: LaunchpadViewModel
    let pager: PagerController
    let drag: GridDragController
    let metrics: LayoutMetrics
    // Apps of the open folder as its popup shows them; nil while no folder
    // is open.
    let folderApps: [AppEntry]?
    // A dragged app left the folder card: close the folder.
    let onLeaveFolder: () -> Void
    // A drop changed the layout; refresh anything showing a snapshot of it.
    let onLayoutChange: () -> Void
    // A drop made a new folder: open it with its title in edit mode.
    let onFolderCreated: (String) -> Void

    // Resets when the gesture ends or is cancelled, which `onEnded` alone
    // doesn't report.
    @GestureState private var isPressing = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                MarqueeView(drag: drag)
            }
            .overlay(alignment: .topLeading) {
                LiftedItemView(drag: drag, metrics: metrics)
            }
            .environment(\.isGridDragActive, drag.isActive)
            .simultaneousGesture(gesture)
            .coordinateSpace(.named(Drag.coordinateSpace))
            .onChange(of: isPressing) { _, pressing in
                guard !pressing else { return }
                // Ended without `onEnded` (cancelled): nothing to persist.
                // After a normal release the session is already dropping and
                // this is a no-op.
                if drag.session?.isDropping == false {
                    drag.cancel()
                }
                viewModel.editing.endDragSession()
                viewModel.editing.endMarquee()
            }
            .onChange(of: viewModel.isVisible) { _, visible in
                guard !visible else { return }
                drag.cancel()
                viewModel.editing.endDragSession()
            }
            // The grid is replaced by search results: its slots mean nothing.
            .onChange(of: viewModel.search.isSearching) { _, searching in
                guard searching else { return }
                drag.cancel()
                viewModel.editing.endDragSession()
            }
            .onChange(of: viewModel.editing.dragCancelRequest) {
                let page = drag.cancelDrop()
                viewModel.editing.endDragSession()
                show(page)
            }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: Drag.threshold, coordinateSpace: .named(Drag.coordinateSpace))
            .updating($isPressing) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard !viewModel.search.isSearching, viewModel.removal.pendingRemoval == nil else { return }
                let lifted = drag.update(
                    start: value.startLocation,
                    pointer: value.location,
                    grid: gridContext,
                    folder: folderContext,
                    flipPage: flipPage,
                    leaveFolder: onLeaveFolder,
                    companions: { viewModel.editing.dragCompanions(for: $0) },
                    marquee: marqueeHandler
                )
                if lifted {
                    viewModel.editing.beginDragSession()
                }
            }
            .onEnded { _ in
                var createdFolderID: String?
                let page = drag.end { session in
                    guard let outcome = viewModel.editing.commitDrop(session) else { return nil }
                    createdFolderID = outcome.createdFolderID
                    return (outcome.page, outcome.slot)
                }
                viewModel.editing.endDragSession()
                onLayoutChange()
                show(page)
                if let createdFolderID {
                    onFolderCreated(createdFolderID)
                }
            }
    }

    // A marquee selects only in edit mode; ⌘ or ⇧ makes it toggle.
    private var marqueeHandler: ((Set<String>) -> Void)? {
        guard viewModel.editing.isEditing else { return nil }
        let editing = viewModel.editing
        return { hits in
            let toggling = !NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty
            editing.updateMarquee(hits: hits, toggling: toggling)
        }
    }

    private var gridContext: GridDragController.GridContext? {
        guard !viewModel.pages.isEmpty, drag.gridFrame.width > 0 else { return nil }
        return GridDragController.GridContext(
            pages: viewModel.pages,
            page: viewModel.currentPage,
            geometry: GridGeometry(metrics: metrics, pageWidth: drag.gridFrame.width),
            frame: drag.gridFrame,
            pagerPosition: pager.position
        )
    }

    private var folderContext: GridDragController.FolderContext? {
        guard let folderID = viewModel.openFolderID, let folderApps, let frames = drag.folderFrames else { return nil }
        return GridDragController.FolderContext(
            folderID: folderID,
            apps: folderApps,
            page: frames.page,
            geometry: .folder(metrics: metrics),
            frames: frames
        )
    }

    // Edge paging: flips by `direction`, adding the trailing empty page when
    // flipping right from the last one. Returns the page now shown.
    private func flipPage(_ direction: Int) -> Int? {
        let current = viewModel.currentPage
        if direction > 0, current + 1 >= viewModel.displayedPageCount {
            guard viewModel.editing.openTrailingDragPage() else { return nil }
        }
        pager.step(by: direction)
        return viewModel.currentPage == current ? nil : viewModel.currentPage
    }

    // Brings the page a dropped icon lands on into view (the drop may have
    // closed up an emptied page, or been refused on another page).
    private func show(_ page: Int?) {
        guard let page else { return }
        pager.syncPageCount()
        let delta = page - viewModel.currentPage
        if delta != 0 {
            pager.step(by: delta)
        }
    }
}

// The rubber band of a marquee selection.
private struct MarqueeView: View {
    let drag: GridDragController

    var body: some View {
        if let rect = drag.marquee {
            Rectangle()
                .fill(.white.opacity(Selection.marqueeFillOpacity))
                .overlay {
                    Rectangle()
                        .strokeBorder(.white.opacity(Selection.marqueeStrokeOpacity), lineWidth: Selection.marqueeLineWidth)
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// The copy of the dragged icon that follows the pointer, lifted above the
// launcher with a scale and a shadow. Reads `drag.location`, so only this
// view re-renders on every mouse move. A group drag stacks up to
// `Selection.stackDepth` of the other selected apps behind it, with a badge
// counting them all.
private struct LiftedItemView: View {
    let drag: GridDragController
    let metrics: LayoutMetrics

    @State private var isLifted = false

    var body: some View {
        if let item = drag.liftedItem {
            let isDropping = drag.session?.isDropping ?? true
            let isMerging = drag.session?.isMerging ?? false
            // Over the folder popup it matches the popup's smaller icons.
            let baseScale = drag.session?.isInFolder == true ? FolderGrid.iconScale : 1
            let liftScale = isMerging ? Drag.mergeDropScale : (isLifted && !isDropping ? Drag.liftScale : 1)
            let companions = drag.liftedCompanions
            let stacked = Array(companions.prefix(Selection.stackDepth).enumerated().reversed())
            let icon = iconOffset
            GridCellView(item: item, metrics: metrics, onLaunch: { _ in }, onOpenFolder: { _ in })
                .background {
                    // Only the icons stack; their labels would pile up.
                    ForEach(stacked, id: \.element.id) { index, app in
                        StackedIcon(app: app, size: metrics.iconSize)
                            .offset(
                                x: icon.width + CGFloat(index + 1) * metrics.iconSize * Selection.stackOffsetRatio,
                                y: icon.height + CGFloat(index + 1) * metrics.iconSize * Selection.stackOffsetRatio
                            )
                            .opacity(isDropping ? 0 : 1)
                    }
                }
                .overlay {
                    if !companions.isEmpty {
                        Text("\(companions.count + 1)")
                            .font(.system(size: metrics.labelFont, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, metrics.labelFont * Selection.badgePaddingRatio)
                            .frame(minWidth: metrics.labelFont * Selection.badgeSizeRatio, minHeight: metrics.labelFont * Selection.badgeSizeRatio)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(
                                x: icon.width + metrics.iconSize / 2,
                                y: icon.height - metrics.iconSize / 2
                            )
                            .opacity(isDropping ? 0 : 1)
                    }
                }
                .scaleEffect(baseScale * liftScale)
                .opacity(isMerging ? 0 : 1)
                .shadow(color: .black.opacity(isLifted && !isDropping ? Drag.shadowOpacity : 0), radius: Drag.shadowRadius)
                .position(drag.location)
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(GridDragController.animation) {
                        isLifted = true
                    }
                }
                .onDisappear {
                    isLifted = false
                }
        }
    }

    // Where the icon's center sits from the cell's center (above it, by
    // half the label).
    private var iconOffset: CGSize {
        let geometry = GridGeometry(metrics: metrics, pageWidth: metrics.itemWidth * CGFloat(Grid.columns))
        let cell = geometry.cellFrame(slot: 0)
        let icon = geometry.iconFrame(slot: 0)
        return CGSize(width: icon.midX - cell.midX, height: icon.midY - cell.midY)
    }
}

// One icon in the stack under a group drag.
private struct StackedIcon: View {
    let app: AppEntry
    let size: CGFloat

    var body: some View {
        Group {
            if let image = IconCache.shared.image(for: app) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
    }
}
