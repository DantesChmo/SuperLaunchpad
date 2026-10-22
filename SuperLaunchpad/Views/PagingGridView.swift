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
struct PagingGridView: View {
    let pages: [[LaunchpadItem]]
    let pager: PagerController
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Index identity is fine: pages are reshuffled holistically
                // rather than reordered.
                ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                    AppGridPageView(items: page, metrics: metrics, onLaunch: onLaunch, onOpenFolder: onOpenFolder)
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .modifier(PagerOffset(pager: pager, pageWidth: geo.size.width))
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            pager.pageWidth = width
        }
        .onChange(of: pages.count) {
            pager.syncPageCount()
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
            .environment(\.isPaging, pager.isPaging)
    }
}

private struct IsPagingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    // True while the main grid is being dragged or is settling.
    var isPaging: Bool {
        get { self[IsPagingKey.self] }
        set { self[IsPagingKey.self] = newValue }
    }
}
