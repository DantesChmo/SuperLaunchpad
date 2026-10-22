import SwiftUI

// The icon drag gesture, on the launcher root. One `DragGesture` for the main
// grid and the open folder: attached here, it survives the folder popup
// closing when a dragged app leaves it. Taps on icons still work because the
// gesture is simultaneous and starts only after `Drag.threshold`.
//
// Also draws the lifted icon above everything (folder popup included) and
// ends the drag when the launcher hides, a search starts, or Esc is pressed.
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
                viewModel.endDragSession()
            }
            .onChange(of: viewModel.isVisible) { _, visible in
                guard !visible else { return }
                drag.cancel()
                viewModel.endDragSession()
            }
            // The grid is replaced by search results: its slots mean nothing.
            .onChange(of: viewModel.isSearching) { _, searching in
                guard searching else { return }
                drag.cancel()
                viewModel.endDragSession()
            }
            .onChange(of: viewModel.dragCancelRequest) {
                let page = drag.cancelDrop()
                viewModel.endDragSession()
                show(page)
            }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: Drag.threshold, coordinateSpace: .named(Drag.coordinateSpace))
            .updating($isPressing) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard !viewModel.isSearching else { return }
                let lifted = drag.update(
                    start: value.startLocation,
                    pointer: value.location,
                    grid: gridContext,
                    folder: folderContext,
                    flipPage: flipPage,
                    leaveFolder: onLeaveFolder
                )
                if lifted {
                    viewModel.beginDragSession()
                }
            }
            .onEnded { _ in
                var createdFolderID: String?
                let page = drag.end { session in
                    guard let outcome = viewModel.commitDrop(session) else { return nil }
                    createdFolderID = outcome.createdFolderID
                    return (outcome.page, outcome.slot)
                }
                viewModel.endDragSession()
                onLayoutChange()
                show(page)
                if let createdFolderID {
                    onFolderCreated(createdFolderID)
                }
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
            guard viewModel.openTrailingDragPage() else { return nil }
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

// The copy of the dragged icon that follows the pointer, lifted above the
// launcher with a scale and a shadow. Reads `drag.location`, so only this
// view re-renders on every mouse move.
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
            GridCellView(item: item, metrics: metrics, onLaunch: { _ in }, onOpenFolder: { _ in })
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
}
