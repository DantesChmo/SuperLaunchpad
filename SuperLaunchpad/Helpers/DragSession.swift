import CoreGraphics
import Foundation

// One icon drag on the main grid, in pure values so it can be unit tested.
// `GridDragController` owns it and feeds it pointer positions.
//
// The pages show a live preview. On the page the item came from, it is taken
// out of `sourceSlot` and re-inserted at `targetSlot`, which is exactly what
// `GridLayout.move(_:toPage:slot:)` does on drop. Once edge paging carried it
// to another page, its source cell stays (hidden) and the item is inserted
// into that page instead.
//
// An app lifted in an open folder starts `isInFolder`: slots are indices into
// the folder's apps and the pages are left alone. Once it leaves the folder
// card it is carried like an item from another page, with the folder's tile
// as its source (where it flies back to when the drop is refused).
//
// Resting the lifted app on the middle of another icon sets
// `mergeTargetID`; a drop then merges into that icon instead of inserting.
struct DragSession: Equatable {
    let itemID: String
    let item: GridLayout.Item
    // The page the item sits on in the view model.
    private(set) var sourcePage: Int
    // Where the item sits on `sourcePage`.
    private(set) var sourceSlot: Int
    // The page shown while dragging, where a drop puts the item.
    private(set) var page: Int
    // Where the preview shows it on `page`, and where a drop puts it.
    private(set) var targetSlot: Int
    // Pointer position minus the center of the grabbed cell, so the lifted
    // icon keeps its place under the pointer instead of jumping to center.
    let grabOffset: CGSize
    // True once the pointer was released: the lifted icon is flying to its
    // cell and no new target is accepted.
    private(set) var isDropping = false
    // The folder an app was lifted from, until a drop takes it out.
    private(set) var sourceFolderID: String?
    // True while that app is still inside the open folder's card.
    private(set) var isInFolder = false
    // The app or folder a drop would merge the lifted app into.
    private(set) var mergeTargetID: String?
    // A refused drop of an app taken out of a folder: it flies back to the
    // folder tile, and no page shows it inserted any more.
    private(set) var isReturningToFolder = false

    init(itemID: String, item: GridLayout.Item, page: Int, slot: Int, grabOffset: CGSize) {
        self.itemID = itemID
        self.item = item
        sourcePage = page
        sourceSlot = slot
        self.page = page
        targetSlot = slot
        self.grabOffset = grabOffset
    }

    // An app lifted at `index` of the open folder `folderID`.
    init(appID: String, folderID: String, index: Int, grabOffset: CGSize) {
        self.init(itemID: appID, item: .app(appID), page: 0, slot: index, grabOffset: grabOffset)
        sourceFolderID = folderID
        isInFolder = true
    }

    // Any drop of an app taken out of its folder changes the layout.
    var hasMoved: Bool { page != sourcePage || targetSlot != sourceSlot || isOutOfFolder }

    var isOutOfFolder: Bool { sourceFolderID != nil && !isInFolder }

    // Whether `page` shows the item inserted at `targetSlot`, rather than
    // moved there from its source cell on the same page.
    var insertsItem: Bool {
        !isInFolder && !isReturningToFolder && (sourceFolderID != nil || page != sourcePage)
    }

    // Dropping into a merge target: the lifted icon shrinks into it.
    var isMerging: Bool { isDropping && mergeTargetID != nil }

    mutating func retarget(_ slot: Int) {
        guard !isDropping else { return }
        targetSlot = slot
    }

    // Edge paging flipped the grid to `page`.
    mutating func switchPage(to page: Int, slot: Int) {
        guard !isDropping else { return }
        self.page = page
        targetSlot = slot
        mergeTargetID = nil
    }

    mutating func setMergeTarget(_ id: String?) {
        guard !isDropping, id != itemID else { return }
        mergeTargetID = id
    }

    // The pointer left the folder card: carry the app over `page`, with the
    // folder's tile (at `tilePage` / `tileSlot`) as where it came from.
    mutating func leaveFolder(tilePage: Int, tileSlot: Int, page: Int, slot: Int) {
        guard isInFolder, !isDropping else { return }
        isInFolder = false
        sourcePage = tilePage
        sourceSlot = tileSlot
        self.page = page
        targetSlot = slot
    }

    mutating func beginDrop() {
        isDropping = true
    }

    // The view model now stores the moved order itself; the preview must stop
    // moving the item on top of it.
    mutating func markCommitted() {
        markCommitted(page: page, slot: targetSlot)
    }

    // As above, when the stored layout put the item somewhere else than the
    // target (a page emptied by the move closed up before it).
    mutating func markCommitted(page: Int, slot: Int) {
        if !isInFolder {
            sourceFolderID = nil
        }
        sourcePage = page
        sourceSlot = slot
        self.page = page
        targetSlot = slot
    }

    // Snaps the preview back to the stored order (drop refused or cancelled).
    mutating func revert() {
        page = sourcePage
        targetSlot = sourceSlot
        mergeTargetID = nil
        if isOutOfFolder {
            isReturningToFolder = true
        }
    }

    // Whether page `index` hides the item's real cell: its source cell, and
    // the copy the preview inserts under the lifted icon.
    func hidesItem(onPage index: Int) -> Bool {
        !isInFolder && (index == page || index == sourcePage)
    }

    // `items` as the source page (or, in a folder, the folder's apps) should
    // show them now. Out-of-range slots (the page changed under the session)
    // leave the order alone.
    func preview<Element>(_ items: [Element]) -> [Element] {
        guard page == sourcePage, !isOutOfFolder, targetSlot != sourceSlot,
              items.indices.contains(sourceSlot), items.indices.contains(targetSlot) else { return items }
        var result = items
        let moved = result.remove(at: sourceSlot)
        result.insert(moved, at: targetSlot)
        return result
    }

    // `items` as page `index` should show them now, with `moved` standing for
    // the dragged item on a page it is carried to. A full page shows only its
    // first `capacity` items; the last one spills to the next page on drop.
    func preview<Element>(_ items: [Element], page index: Int, moved: Element, capacity: Int) -> [Element] {
        guard index == page, !isInFolder else { return items }
        guard insertsItem else { return preview(items) }
        var result = items
        result.insert(moved, at: min(targetSlot, result.count))
        return Array(result.prefix(capacity))
    }
}

// Turns "the pointer is in an edge zone" samples into page flips: the first
// after `Drag.edgeDwell`, then one every `Drag.edgeRepeat` while the pointer
// stays in the same zone. Leaving the zone starts over. Time is passed in, so
// the caller decides the clock.
struct EdgeDwell: Equatable {
    // -1 / +1 for the left / right zone, nil outside both.
    private(set) var direction: Int?
    // When the next flip is due, while in a zone.
    private(set) var deadline: TimeInterval?

    // Returns the direction to flip when this sample makes a flip due.
    mutating func update(direction: Int?, now: TimeInterval) -> Int? {
        guard direction == self.direction else {
            self.direction = direction
            deadline = direction == nil ? nil : now + Drag.edgeDwell
            return nil
        }
        guard let direction, let deadline, now >= deadline else { return nil }
        self.deadline = now + Drag.edgeRepeat
        return direction
    }

    mutating func reset() {
        direction = nil
        deadline = nil
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
