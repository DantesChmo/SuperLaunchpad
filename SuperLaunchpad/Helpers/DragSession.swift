import CoreGraphics

// One icon drag on the main grid, in pure values so it can be unit tested.
// `GridDragController` owns it and feeds it pointer positions.
//
// The page shows a live preview: the dragged item is taken out of
// `sourceSlot` and re-inserted at `targetSlot`, which is exactly what
// `GridLayout.move(_:toPage:slot:)` does on drop.
struct DragSession: Equatable {
    let itemID: String
    let item: GridLayout.Item
    // The page being reordered. Fixed for now; edge paging (stage 3 B2)
    // will move the session to the neighbouring page.
    var page: Int
    // Where the item sits in the page currently shown by the view model.
    private(set) var sourceSlot: Int
    // Where the preview shows it, and where a drop puts it.
    private(set) var targetSlot: Int
    // Pointer position minus the center of the grabbed cell, so the lifted
    // icon keeps its place under the pointer instead of jumping to center.
    let grabOffset: CGSize
    // True once the pointer was released: the lifted icon is flying to its
    // cell and no new target is accepted.
    private(set) var isDropping = false

    init(itemID: String, item: GridLayout.Item, page: Int, slot: Int, grabOffset: CGSize) {
        self.itemID = itemID
        self.item = item
        self.page = page
        sourceSlot = slot
        targetSlot = slot
        self.grabOffset = grabOffset
    }

    var hasMoved: Bool { targetSlot != sourceSlot }

    mutating func retarget(_ slot: Int) {
        guard !isDropping else { return }
        targetSlot = slot
    }

    mutating func beginDrop() {
        isDropping = true
    }

    // The view model now stores the moved order itself; the preview must stop
    // moving the item on top of it.
    mutating func markCommitted() {
        sourceSlot = targetSlot
    }

    // Snaps the preview back to the stored order (drop refused or cancelled).
    mutating func revert() {
        targetSlot = sourceSlot
    }

    // `items` as the page should show them now. Out-of-range slots (the page
    // changed under the session) leave the order alone.
    func preview<Element>(_ items: [Element]) -> [Element] {
        guard hasMoved, items.indices.contains(sourceSlot), items.indices.contains(targetSlot) else { return items }
        var result = items
        let moved = result.remove(at: sourceSlot)
        result.insert(moved, at: targetSlot)
        return result
    }
}

extension LaunchpadItem {
    var layoutItem: GridLayout.Item {
        switch self {
        case .app(let app): .app(app.bundleIdentifier)
        case .folder(let folder, _): .folder(folder.id)
        }
    }
}
