import SwiftUI

// One page of the grid: a fixed N×M layout of apps and/or folders.
struct AppGridPageView: View {
    let items: [LaunchpadItem]
    let metrics: LayoutMetrics
    // The keyboard-selected app in search results; nil on the main grid.
    var selectedID: String? = nil
    let onLaunch: (AppEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void
    // Item currently lifted by a drag, if it is on this page.
    var hiddenItemID: String? = nil

    var body: some View {
        VStack {
            // An eager layout instead of `LazyVGrid`: a lazy grid builds its
            // cells the first time the page slides into view, which hitched
            // the first swipe to every page. All cells of a page are created
            // with the page itself. A flat `ForEach` (rather than row stacks)
            // keeps each item's identity stable when it moves between rows.
            FixedColumnsLayout(
                columns: Grid.columns,
                itemWidth: metrics.itemWidth,
                itemHeight: metrics.itemHeight,
                rowSpacing: metrics.rowSpacing
            ) {
                ForEach(items) { item in
                    GridCellView(item: item, metrics: metrics, isSelected: item.id == selectedID, onLaunch: onLaunch, onOpenFolder: onOpenFolder)
                        // The dragged item keeps its slot (so the reflow
                        // around it is right) but is drawn by the lifted copy.
                        .opacity(item.id == hiddenItemID ? 0 : 1)
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            // Pushes the grid to the top of the page so partial rows hug the
            // top edge instead of floating in the middle of the page.
            Spacer(minLength: 0)
        }
    }
}

// One grid cell: the icon centered in an `itemWidth` × `itemHeight` box.
// Also drawn by the lifted copy of a dragged icon.
struct GridCellView: View {
    let item: LaunchpadItem
    let metrics: LayoutMetrics
    var isSelected = false
    let onLaunch: (AppEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void

    var body: some View {
        // Cell layout trick: wrap each icon in a VStack with top/bottom
        // Spacers. The Spacers absorb leftover vertical space, so the icon
        // centers vertically within `itemHeight` regardless of label line
        // count (1 vs. 2 lines).
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            // `switch` over the LaunchpadItem sum type — each case gets
            // compile-time exhaustiveness checking.
            switch item {
            case .app(let app):
                AppIconView(app: app, metrics: metrics, isSelected: isSelected) {
                    onLaunch(app)
                }
            case .folder(let folder, let apps):
                FolderIconView(folder: folder, apps: apps, metrics: metrics) {
                    onOpenFolder(folder)
                }
            }
            Spacer(minLength: 0)
        }
        // Full column width centers the icon in its column, as the `.fixed`
        // columns of the old `LazyVGrid` did.
        .frame(width: metrics.itemWidth, height: metrics.itemHeight)
    }
}

// Places subviews left to right in `columns` fixed-width columns, wrapping to
// a new row every `columns` items. The width is always the full column count,
// so a page with a single partial row lines up with full pages.
private struct FixedColumnsLayout: Layout {
    let columns: Int
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rowCount(for: subviews.count)
        let height = CGFloat(rows) * itemHeight + CGFloat(max(rows - 1, 0)) * rowSpacing
        return CGSize(width: CGFloat(columns) * itemWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard columns > 0 else { return }
        let cellProposal = ProposedViewSize(width: itemWidth, height: itemHeight)
        for (index, subview) in subviews.enumerated() {
            let column = index % columns
            let row = index / columns
            let origin = CGPoint(
                x: bounds.minX + CGFloat(column) * itemWidth,
                y: bounds.minY + CGFloat(row) * (itemHeight + rowSpacing)
            )
            subview.place(at: origin, anchor: .topLeading, proposal: cellProposal)
        }
    }

    private func rowCount(for count: Int) -> Int {
        guard columns > 0 else { return 0 }
        return (count + columns - 1) / columns
    }
}
