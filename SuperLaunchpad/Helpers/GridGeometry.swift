import CoreGraphics

// Pure slot math for one page of the main grid. Mirrors what
// `AppGridPageView` draws: `columns` fixed-width cells centered horizontally on
// the page and hugging its top edge, `rowSpacing` between rows, and an icon +
// label hit box centered in each cell (see `GridItemContainer`).
//
// Points are page-local: (0, 0) is the top-left corner of the page.
struct GridGeometry: Equatable {
    let columns: Int
    let rows: Int
    let cellSize: CGSize
    let rowSpacing: CGFloat
    let hitSize: CGSize
    // Top-left corner of slot 0.
    let origin: CGPoint

    init(columns: Int, rows: Int, cellSize: CGSize, rowSpacing: CGFloat, hitSize: CGSize, pageWidth: CGFloat) {
        self.columns = columns
        self.rows = rows
        self.cellSize = cellSize
        self.rowSpacing = rowSpacing
        self.hitSize = hitSize
        origin = CGPoint(x: (pageWidth - CGFloat(columns) * cellSize.width) / 2, y: 0)
    }

    init(metrics: LayoutMetrics, pageWidth: CGFloat) {
        self.init(
            columns: Grid.columns,
            rows: Grid.rows,
            cellSize: CGSize(width: metrics.itemWidth, height: metrics.itemHeight),
            rowSpacing: metrics.rowSpacing,
            hitSize: metrics.itemHitSize,
            pageWidth: pageWidth
        )
    }

    var capacity: Int { columns * rows }

    func cellFrame(slot: Int) -> CGRect {
        let column = slot % columns
        let row = slot / columns
        return CGRect(
            x: origin.x + CGFloat(column) * cellSize.width,
            y: origin.y + CGFloat(row) * (cellSize.height + rowSpacing),
            width: cellSize.width,
            height: cellSize.height
        )
    }

    func hitFrame(slot: Int) -> CGRect {
        let cell = cellFrame(slot: slot)
        return CGRect(
            x: cell.midX - hitSize.width / 2,
            y: cell.midY - hitSize.height / 2,
            width: hitSize.width,
            height: hitSize.height
        )
    }

    // The occupied slot whose icon + label box contains `point`; nil over a
    // gap or an empty cell. Used to pick the item a drag starts on.
    func item(at point: CGPoint, itemCount: Int) -> Int? {
        guard let slot = nearestSlot(to: point), slot < itemCount else { return nil }
        return hitFrame(slot: slot).contains(point) ? slot : nil
    }

    // Where an item dragged within this page lands when dropped at `point`:
    // the cell under the pointer (the nearest one outside the grid), clamped
    // to the page's occupied slots — the dragged item itself is one of the
    // `itemCount`, so a page never grows.
    func dropSlot(at point: CGPoint, itemCount: Int) -> Int {
        guard itemCount > 0, let slot = nearestSlot(to: point) else { return 0 }
        return min(slot, itemCount - 1)
    }

    // The cell under `point`, with points outside the grid clamped to the
    // nearest row / column. Half the row spacing belongs to each neighbouring
    // row.
    private func nearestSlot(to point: CGPoint) -> Int? {
        guard columns > 0, rows > 0, cellSize.width > 0, cellSize.height > 0 else { return nil }
        let column = Int(((point.x - origin.x) / cellSize.width).rounded(.down))
        let rowPitch = cellSize.height + rowSpacing
        let row = Int(((point.y - origin.y + rowSpacing / 2) / rowPitch).rounded(.down))
        let clampedColumn = min(max(column, 0), columns - 1)
        let clampedRow = min(max(row, 0), rows - 1)
        return clampedRow * columns + clampedColumn
    }

    // Converts a point in the pager's (unscrolled) container to page-local
    // coordinates of `page`, given the pager's current position in pages.
    static func pageLocal(_ point: CGPoint, page: Int, pagerPosition: Double, pageWidth: CGFloat) -> CGPoint {
        CGPoint(x: point.x + (CGFloat(pagerPosition) - CGFloat(page)) * pageWidth, y: point.y)
    }

    // Inverse of `pageLocal`.
    static func containerPoint(_ point: CGPoint, page: Int, pagerPosition: Double, pageWidth: CGFloat) -> CGPoint {
        CGPoint(x: point.x - (CGFloat(pagerPosition) - CGFloat(page)) * pageWidth, y: point.y)
    }
}
