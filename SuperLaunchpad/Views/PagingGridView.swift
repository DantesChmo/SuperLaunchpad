import SwiftUI

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

// Horizontal pager: a ScrollView whose children are `AppGridPageView`s.
struct PagingGridView: View {
    let pages: [[LaunchpadItem]]
    // `@Binding` makes the page index two-way — keyboard/scroll updates flow
    // from the parent ViewModel down here, and swipe updates flow back up.
    @Binding var currentPage: Int
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void

    // Tracks the last page index that was set by a gesture (vs. set
    // programmatically from outside). See the `onChange` below — used to
    // avoid re-animating a scroll that was just driven by the user.
    @State private var lastGesturePage: Int = 0

    var body: some View {
        // `ScrollViewReader` exposes a `proxy.scrollTo(id:)` for programmatic
        // scrolling — used when the user presses an arrow key.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // `Array(pages.enumerated())` is needed because ForEach
                    // can't directly take an `EnumeratedSequence`. `id: \.offset`
                    // uses the index as identity, which is fine since pages
                    // are reshuffled holistically rather than reordered.
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        AppGridPageView(items: page, metrics: metrics, onLaunch: onLaunch, onOpenFolder: onOpenFolder)
                            .contentShape(Rectangle())
                            // Each page fills the ScrollView's visible width
                            // exactly — `containerRelativeFrame` does this
                            // without needing a GeometryReader.
                            .containerRelativeFrame(.horizontal)
                            // `.id(index)` is the anchor used by `scrollTo`.
                            .id(index)
                    }
                }
                // Marks the HStack as the "target layout" for snap behaviors.
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(SinglePageBehavior())
            // Modern API (iOS 17 / macOS 14+) that reports scroll geometry
            // changes. We compute the current page from the content offset
            // and write it back to the binding.
            .onScrollGeometryChange(for: Int.self) { geometry in
                let pageWidth = geometry.containerSize.width
                guard pageWidth > 0 else { return 0 }
                let page = Int(round(geometry.contentOffset.x / pageWidth))
                return max(0, min(page, pages.count - 1))
            } action: { _, newValue in
                lastGesturePage = newValue
                currentPage = newValue
            }
            // Programmatic page change (arrow key, mouse wheel) → animate
            // scroll. Guard: if `currentPage` was just updated by the
            // gesture handler above, the ScrollView is already there;
            // re-animating would cause a tiny stutter.
            .onChange(of: currentPage) { _, newValue in
                guard newValue != lastGesturePage else { return }
                withAnimation(.spring(duration: 0.35, bounce: 0)) {
                    proxy.scrollTo(newValue, anchor: .leading)
                }
            }
        }
    }
}
