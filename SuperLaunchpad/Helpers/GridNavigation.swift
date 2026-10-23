import Foundation

// Where the keyboard focus sits in a paged grid: the page and the index of
// the item on it, in reading order.
struct GridPosition: Equatable, Hashable {
    var page: Int
    var index: Int
}

// Arrow-key moves over a paged grid (the launcher's pages or an open folder's).
// Pure: it only knows how many items each page holds and how many columns a
// row has, so it follows whatever grid size the caller passes (`Grid`,
// `FolderGrid`), and any page may end in a partial row.
enum GridNavigation {
    enum Direction: Equatable, CaseIterable {
        case left, right, up, down
    }

    // The position after one arrow press. Left and right walk the row and,
    // at its first or last item, cross to the neighbouring page on the same
    // row (its last item when that page has no such column or row). Up and
    // down stay on the page; down from above a partial last row lands on its
    // last item. With nowhere to go the position stays as it is.
    static func move(
        _ position: GridPosition,
        _ direction: Direction,
        pageCounts: [Int],
        columns: Int
    ) -> GridPosition {
        guard columns > 0, pageCounts.indices.contains(position.page) else { return position }
        let count = pageCounts[position.page]
        guard count > 0 else { return position }
        let index = min(max(position.index, 0), count - 1)
        let row = index / columns
        let column = index % columns
        let lastRow = (count - 1) / columns

        switch direction {
        case .left:
            if column > 0 {
                return GridPosition(page: position.page, index: index - 1)
            }
            return neighbour(of: position.page, by: -1, row: row, column: columns - 1, pageCounts: pageCounts, columns: columns)
                ?? GridPosition(page: position.page, index: index)
        case .right:
            if column < columns - 1, index + 1 < count {
                return GridPosition(page: position.page, index: index + 1)
            }
            return neighbour(of: position.page, by: 1, row: row, column: 0, pageCounts: pageCounts, columns: columns)
                ?? GridPosition(page: position.page, index: index)
        case .up:
            return GridPosition(page: position.page, index: row > 0 ? index - columns : index)
        case .down:
            guard row < lastRow else { return GridPosition(page: position.page, index: index) }
            return GridPosition(page: position.page, index: min(index + columns, count - 1))
        }
    }

    // How many items each page of a flat list holds, `perPage` at most: the
    // pages of an open folder.
    static func pageCounts(itemCount: Int, perPage: Int) -> [Int] {
        guard itemCount > 0, perPage > 0 else { return [] }
        return stride(from: 0, to: itemCount, by: perPage).map { min(perPage, itemCount - $0) }
    }

    // `index` in a flat list split into pages of `perPage`.
    static func position(ofFlatIndex index: Int, perPage: Int) -> GridPosition {
        guard perPage > 0 else { return GridPosition(page: 0, index: index) }
        return GridPosition(page: index / perPage, index: index % perPage)
    }

    // The item at `row`, `column` of the page `delta` pages away, or the last
    // item there when that page is shorter; nil past the first or last page,
    // or when that page is empty.
    private static func neighbour(
        of page: Int,
        by delta: Int,
        row: Int,
        column: Int,
        pageCounts: [Int],
        columns: Int
    ) -> GridPosition? {
        let target = page + delta
        guard pageCounts.indices.contains(target), pageCounts[target] > 0 else { return nil }
        return GridPosition(page: target, index: min(row * columns + column, pageCounts[target] - 1))
    }
}
