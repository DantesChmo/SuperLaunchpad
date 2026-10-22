import SwiftUI

// Used by `FolderDetailView`'s ScrollView pager. The main grid uses
// `PagerController` instead.
//
// Custom `ScrollTargetBehavior` that limits a horizontal scroll fling to ONE
// page at a time — even if the user swipes hard enough to "throw" past several
// pages. macOS Launchpad behaves this way; the default `.paging` behavior
// allows multi-page momentum.
//
// `ScrollTargetBehavior` was introduced in iOS 17 / macOS 14. It hooks into
// the scroll system: when the user releases their finger, AppKit/UIKit picks
// a final resting offset and asks us to optionally adjust it.
struct SinglePageBehavior: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let pageWidth = context.containerSize.width
        guard pageWidth > 0 else { return }

        // Convert offsets to "page units" (e.g. 2.4 = somewhere between
        // pages 2 and 3). `originalTarget` is where the user started the
        // gesture; `target` is where momentum would naturally land.
        let currentPage = context.originalTarget.rect.minX / pageWidth
        let proposedPage = target.rect.minX / pageWidth

        // Clamp the proposed destination to ±1 page from where we started —
        // this is what enforces "one page per swipe".
        let clamped = proposedPage.rounded().clamped(to: currentPage.rounded() - 1 ... currentPage.rounded() + 1)
        target.rect.origin.x = clamped * pageWidth
    }
}

// Private extension — only visible in this file. `clamp` isn't in the Swift
// stdlib, so we add a tiny convenience.
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// Main-grid pager: all pages side by side in an HStack, shifted by
// `-position * width`. Input and the settle spring live in `PagerController`;
// there is no ScrollView, so nothing else competes for the offset.
//
// Drag-to-reorder: a click-drag on an icon lifts it (`GridDragController`).
// The pager only listens to scroll events, so a mouse drag never pages and a
// trackpad swipe never reorders. Holding the lifted icon beside the grid flips
// the page (edge paging); past the last page an empty one is added.
struct PagingGridView: View {
    let viewModel: LaunchpadViewModel
    let pages: [[LaunchpadItem]]
    let pager: PagerController
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void

    @State private var drag = GridDragController()
    // Resets when the gesture ends or is cancelled, which `onEnded` alone
    // doesn't report.
    @GestureState private var isPressing = false

    private static let coordinateSpace = "pagingGrid"

    var body: some View {
        GeometryReader { geo in
            let geometry = GridGeometry(metrics: metrics, pageWidth: geo.size.width)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    // Index identity is fine: pages are reshuffled holistically
                    // rather than reordered.
                    ForEach(Array(shownPages.enumerated()), id: \.offset) { index, page in
                        AppGridPageView(
                            items: previewItems(page, index: index),
                            metrics: metrics,
                            onLaunch: { app in
                                guard !drag.isTapSuppressed else { return }
                                onLaunch(app)
                            },
                            onOpenFolder: { folder in
                                guard !drag.isTapSuppressed else { return }
                                onOpenFolder(folder)
                            },
                            hiddenItemID: drag.session?.hidesItem(onPage: index) == true ? drag.session?.itemID : nil
                        )
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width)
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .modifier(PagerOffset(pager: pager, pageWidth: geo.size.width))

                LiftedItemView(drag: drag, metrics: metrics)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .environment(\.isGridDragActive, drag.isActive)
            .simultaneousGesture(reorderGesture(geometry: geometry, pageWidth: geo.size.width))
            .coordinateSpace(.named(Self.coordinateSpace))
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            pager.pageWidth = width
        }
        .onChange(of: viewModel.displayedPageCount) {
            pager.syncPageCount()
        }
        .onChange(of: isPressing) { _, pressing in
            guard !pressing else { return }
            // Ended without `onEnded` (cancelled): nothing to persist. After a
            // normal release the session is already dropping and this is a no-op.
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
        .onChange(of: viewModel.dragCancelRequest) {
            let page = drag.cancelDrop()
            viewModel.endDragSession()
            show(page)
        }
    }

    private var shownPages: [[LaunchpadItem]] {
        viewModel.hasTrailingDragPage ? pages + [[]] : pages
    }

    private func previewItems(_ items: [LaunchpadItem], index: Int) -> [LaunchpadItem] {
        guard let session = drag.session, let lifted = drag.liftedItem else { return items }
        return session.preview(items, page: index, moved: lifted, capacity: Grid.appsPerPage)
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

    // Where the dropped item sits in the stored layout after a commit.
    private func storedLocation(of itemID: String) -> (page: Int, slot: Int)? {
        for (page, items) in viewModel.pages.enumerated() {
            if let slot = items.firstIndex(where: { $0.id == itemID }) {
                return (page, slot)
            }
        }
        return nil
    }

    private func reorderGesture(geometry: GridGeometry, pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: Drag.threshold, coordinateSpace: .named(Self.coordinateSpace))
            .updating($isPressing) { _, state, _ in
                state = true
            }
            .onChanged { value in
                let lifted = drag.update(
                    start: value.startLocation,
                    pointer: value.location,
                    pages: pages,
                    page: viewModel.currentPage,
                    geometry: geometry,
                    pagerPosition: pager.position,
                    pageWidth: pageWidth,
                    flipPage: flipPage
                )
                if lifted {
                    viewModel.beginDragSession()
                }
            }
            .onEnded { _ in
                let page = drag.end { session in
                    guard viewModel.moveItem(session.item, toPage: session.page, slot: session.targetSlot) else { return nil }
                    return storedLocation(of: session.itemID)
                }
                viewModel.endDragSession()
                show(page)
            }
    }
}

// The copy of the dragged icon that follows the pointer, lifted above the
// grid with a scale and a shadow. Reads `drag.location`, so only this view
// re-renders on every mouse move.
private struct LiftedItemView: View {
    let drag: GridDragController
    let metrics: LayoutMetrics

    @State private var isLifted = false

    var body: some View {
        if let item = drag.liftedItem {
            let isDropping = drag.session?.isDropping ?? true
            GridCellView(item: item, metrics: metrics, onLaunch: { _ in }, onOpenFolder: { _ in })
                .scaleEffect(isLifted && !isDropping ? Drag.liftScale : 1)
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

// The only place that reads `pager.position`, so a per-frame change re-runs
// this modifier and not the pages inside `content`.
private struct PagerOffset: ViewModifier {
    let pager: PagerController
    let pageWidth: CGFloat

    func body(content: Content) -> some View {
        let offset = -CGFloat(pager.position) * pageWidth
        content
            .offset(x: offset)
            // The pager animates itself; an enclosing implicit animation
            // (e.g. the show fade) must not tween the offset as well.
            .transaction(value: offset) { transaction in
                transaction.animation = nil
            }
            // While paging, icons slide under a still cursor: disable hit
            // testing so hover can't start mid-swipe, and absorb clicks so
            // they don't fall through to the launcher's tap-to-hide.
            .allowsHitTesting(!pager.isPaging)
            .overlay {
                if pager.isPaging {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {}
                }
            }
    }
}
