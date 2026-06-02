import SwiftUI

struct SinglePageBehavior: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let pageWidth = context.containerSize.width
        guard pageWidth > 0 else { return }

        let currentPage = context.originalTarget.rect.minX / pageWidth
        let proposedPage = target.rect.minX / pageWidth

        let clamped = proposedPage.rounded().clamped(to: currentPage.rounded() - 1 ... currentPage.rounded() + 1)
        target.rect.origin.x = clamped * pageWidth
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct PagingGridView: View {
    let pages: [[LaunchpadItem]]
    @Binding var currentPage: Int
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void

    @State private var lastGesturePage: Int = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        AppGridPageView(items: page, metrics: metrics, onLaunch: onLaunch, onOpenFolder: onOpenFolder)
                            .contentShape(Rectangle())
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(SinglePageBehavior())
            .onScrollGeometryChange(for: Int.self) { geometry in
                let pageWidth = geometry.containerSize.width
                guard pageWidth > 0 else { return 0 }
                let page = Int(round(geometry.contentOffset.x / pageWidth))
                return max(0, min(page, pages.count - 1))
            } action: { _, newValue in
                lastGesturePage = newValue
                currentPage = newValue
            }
            .onChange(of: currentPage) { _, newValue in
                guard newValue != lastGesturePage else { return }
                withAnimation(.spring(duration: 0.35, bounce: 0)) {
                    proxy.scrollTo(newValue, anchor: .leading)
                }
            }
        }
    }
}
