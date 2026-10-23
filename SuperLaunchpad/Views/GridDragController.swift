import AppKit
import SwiftUI

// Drives icon drags: reorder on the main grid, reorder inside an open
// folder, dragging an app out of its folder onto the grid, and merging an
// app into another icon (new folder / add to folder). Turns `DragGesture`
// updates into a `DragSession`, debounces slot changes with a short dwell,
// flips pages while the pointer rests beside the grid, and runs the lift /
// reflow / merge / drop animations. The slot math lives in `GridGeometry`.
//
// The gesture sits on the launcher root (see `LaunchpadDragGesture`), so it
// survives the folder popup closing under a dragged app. All points are in
// the root's coordinate space (`Drag.coordinateSpace`); the views report
// where the pager and the folder grid are (`gridFrame`, `folderFrames`).
//
// Observation is split so a mouse move re-renders only the lifted icon:
// `location` changes every event and is read by the overlay alone, while
// `session` (read by the pages) changes only when the target slot does.
//
// Slots are computed for the page the pager settles on (`session.page`), not
// for the mid-flight position, so a target stays put while the pages slide.
//
// A group drag (multi-select) lifts the selected apps with the one grabbed;
// every page and folder list below is read without them (`lifting`). In
// edit mode a press outside any icon draws a marquee instead.
@MainActor
@Observable
final class GridDragController {
    // The main grid as the gesture sees it.
    struct GridContext {
        var pages: [[LaunchpadItem]]
        // The page shown (`viewModel.currentPage`).
        var page: Int
        // Page-local slot math.
        var geometry: GridGeometry
        // The pager container, in root coordinates.
        var frame: CGRect
        var pagerPosition: Double
    }

    // An open folder as the gesture sees it.
    struct FolderContext {
        var folderID: String
        var apps: [AppEntry]
        // The folder page shown.
        var page: Int
        // Slot math local to `gridFrame`.
        var geometry: GridGeometry
        var frames: FolderFrames
    }

    // Where the open folder's card and grid are, in root coordinates.
    struct FolderFrames: Equatable {
        var card: CGRect
        var grid: CGRect
        var page: Int
    }

    private(set) var session: DragSession?
    // The lifted icon's center, in root coordinates.
    private(set) var location: CGPoint = .zero
    private(set) var liftedItem: LaunchpadItem?
    // The selected apps a group drag carries under the lifted icon.
    private(set) var liftedCompanions: [AppEntry] = []
    // The rubber band being drawn, in root coordinates.
    private(set) var marquee: CGRect?

    // A click on an icon that turned into a drag must not also launch it or
    // open its folder. Stays set until just after the drag ends.
    @ObservationIgnored private(set) var isTapSuppressed = false

    // Reported by `PagingGridView` and `FolderDetailView`.
    @ObservationIgnored var gridFrame: CGRect = .zero
    @ObservationIgnored var folderFrames: FolderFrames?

    // Edge paging: asks the grid to flip by -1 / +1 and returns the page now
    // shown, or nil when it could not flip. Set with every `update`.
    @ObservationIgnored private var flipPage: (Int) -> Int? = { _ in nil }
    // Closes the open folder when a dragged app leaves its card.
    @ObservationIgnored private var leaveFolder: () -> Void = {}
    private let clock: () -> TimeInterval

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    @ObservationIgnored private var phase = Phase.idle
    @ObservationIgnored private var grid: GridContext?
    @ObservationIgnored private var folder: FolderContext?
    @ObservationIgnored private var pointer: CGPoint = .zero
    @ObservationIgnored private var pendingSlot: Int?
    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    // The icon the lifted app rests on, until `Drag.mergeDwell` makes it the
    // merge target.
    @ObservationIgnored private(set) var pendingMerge: String?
    @ObservationIgnored private var mergeTask: Task<Void, Never>?
    @ObservationIgnored private var edge = EdgeDwell()
    @ObservationIgnored private var edgeTask: Task<Void, Never>?

    private enum Phase {
        case idle
        // The press started outside any icon, or the drag was cancelled with
        // Esc; ignore the rest of it.
        case ignored
        case dragging
        // Drawing a marquee from an empty spot in edit mode.
        case marquee
    }

    var isActive: Bool { session != nil }

    // MARK: - Gesture input

    // Feeds one `DragGesture` change, in root coordinates. `folder` is the
    // open folder, if any: while one is open only its apps can be lifted.
    // `companions` gives the apps a lift of the given app carries along (the
    // rest of the selection). With `marquee` set, a press on the grid
    // outside any icon draws a band and reports the apps under it.
    // Returns true when this update lifted an icon.
    @discardableResult
    func update(
        start: CGPoint,
        pointer: CGPoint,
        grid: GridContext?,
        folder: FolderContext? = nil,
        flipPage: @escaping (Int) -> Int?,
        leaveFolder: @escaping () -> Void = {},
        companions: (String) -> [AppEntry] = { _ in [] },
        marquee report: ((Set<String>) -> Void)? = nil
    ) -> Bool {
        self.grid = grid
        // Keep the last folder seen while the drag is in it, for the landing.
        if folder != nil || session?.isInFolder != true {
            self.folder = folder
        }
        self.flipPage = flipPage
        self.leaveFolder = leaveFolder
        switch phase {
        case .ignored:
            return false
        case .marquee:
            if let report {
                updateMarquee(start: start, pointer: pointer, report: report)
            }
            return false
        case .idle:
            // A drop is still flying home: don't start a second drag on top.
            guard session == nil, let lifted = lift(at: start, companions: companions) else {
                if session == nil, let report, folder == nil, let grid, grid.frame.contains(start) {
                    phase = .marquee
                    isTapSuppressed = true
                    updateMarquee(start: start, pointer: pointer, report: report)
                } else {
                    phase = .ignored
                }
                return false
            }
            phase = .dragging
            isTapSuppressed = true
            liftedItem = lifted.item
            liftedCompanions = lifted.companions
            session = lifted.session
            move(to: pointer)
            return true
        case .dragging:
            if session?.isInFolder == true, folder == nil {
                // The folder closed under the drag (not by leaving the card).
                leaveFolderCard()
            }
            move(to: pointer)
            return false
        }
    }

    // Releases the pointer. `commit` persists the drop (the view model's
    // `commitDrop`) and returns where the item ended up, or nil when the
    // edit was refused; the lifted icon then flies back to where it came
    // from. Returns the grid page the icon lands on, for the pager to show
    // (nil for a drop inside a folder).
    @discardableResult
    func end(commit: (DragSession) -> (page: Int, slot: Int)?) -> Int? {
        defer { finishGesture() }
        guard phase == .dragging, var session else { return nil }
        cancelTimers()
        // The drop lands where the pointer is now, dwell or not.
        if session.isInFolder {
            if let slot = folderSlot(for: location) {
                session.retarget(slot)
            }
        } else if session.mergeTargetID == nil, let slot = dropSlot(for: location, session: session) {
            session.retarget(slot)
        }
        if (session.hasMoved || session.mergeTargetID != nil), isValid(session), let landed = commit(session) {
            session.markCommitted(page: landed.page, slot: landed.slot)
        } else {
            session.revert()
        }
        session.beginDrop()
        land(session)
        return session.isInFolder ? nil : session.page
    }

    // Esc while dragging: the icon flies back to its source cell and the rest
    // of the gesture is ignored. Returns the source page, for the pager to
    // show, or nil when no drag was in progress (or it was in a folder).
    @discardableResult
    func cancelDrop() -> Int? {
        guard phase == .dragging, var session, !session.isDropping else { return nil }
        cancelTimers()
        phase = .ignored
        session.revert()
        session.beginDrop()
        land(session)
        return session.isInFolder ? nil : session.page
    }

    // The gesture went away without a release (panel hidden, search started):
    // drop everything without persisting or animating.
    func cancel() {
        cancelTimers()
        session = nil
        liftedItem = nil
        liftedCompanions = []
        finishGesture()
    }

    // MARK: - Private

    private func lift(
        at start: CGPoint,
        companions: (String) -> [AppEntry]
    ) -> (item: LaunchpadItem, companions: [AppEntry], session: DragSession)? {
        if let folder {
            guard folder.frames.card.contains(start) else { return nil }
            let first = folder.page * FolderGrid.appsPerPage
            let local = start - folder.frames.grid.origin
            guard let slot = folder.geometry.item(at: local, itemCount: folderPageCount(folder, appCount: folder.apps.count)),
                  folder.apps.indices.contains(first + slot) else { return nil }
            let app = folder.apps[first + slot]
            let group = companions(app.id)
            let companionIDs = Set(group.map(\.id))
            let cell = folder.geometry.cellFrame(slot: slot)
            let session = DragSession(
                appID: app.id,
                folderID: folder.folderID,
                index: folder.apps.filter { !companionIDs.contains($0.id) }.firstIndex { $0.id == app.id } ?? first + slot,
                grabOffset: CGSize(width: local.x - cell.midX, height: local.y - cell.midY),
                companionIDs: group.map(\.id)
            )
            return (.app(app), group, session)
        }
        guard let grid, grid.pages.indices.contains(grid.page) else { return nil }
        let local = GridGeometry.pageLocal(
            start - grid.frame.origin,
            page: grid.page,
            pagerPosition: grid.pagerPosition,
            pageWidth: grid.frame.width
        )
        guard let slot = grid.geometry.item(at: local, itemCount: grid.pages[grid.page].count) else { return nil }
        let item = grid.pages[grid.page][slot]
        let group: [AppEntry]
        if case .app = item {
            group = companions(item.id)
        } else {
            group = []
        }
        let companionIDs = Set(group.map(\.id))
        let cell = grid.geometry.cellFrame(slot: slot)
        let session = DragSession(
            itemID: item.id,
            item: item.layoutItem,
            page: grid.page,
            slot: grid.pages[grid.page].filter { !companionIDs.contains($0.id) }.firstIndex { $0.id == item.id } ?? slot,
            grabOffset: CGSize(width: local.x - cell.midX, height: local.y - cell.midY),
            companionIDs: group.map(\.id)
        )
        return (item, group, session)
    }

    // The band from `start` to `pointer`, and the apps on the shown page
    // whose icon + label box it touches.
    private func updateMarquee(start: CGPoint, pointer: CGPoint, report: (Set<String>) -> Void) {
        let rect = GridGeometry.marqueeRect(from: start, to: pointer)
        marquee = rect
        guard let grid, grid.pages.indices.contains(grid.page) else { return }
        let origin = GridGeometry.pageLocal(
            CGPoint(x: rect.minX, y: rect.minY) - grid.frame.origin,
            page: grid.page,
            pagerPosition: grid.pagerPosition,
            pageWidth: grid.frame.width
        )
        let local = CGRect(origin: origin, size: rect.size)
        let items = grid.pages[grid.page]
        let hits = grid.geometry.slots(intersecting: local, itemCount: items.count).compactMap { slot -> String? in
            guard case .app(let app) = items[slot] else { return nil }
            return app.id
        }
        report(Set(hits))
    }

    // Page `index` as a session's slots count it: without its companions.
    private func items(onPage index: Int, of grid: GridContext, for session: DragSession) -> [LaunchpadItem] {
        grid.pages.indices.contains(index) ? session.lifting(grid.pages[index]) : []
    }

    private func move(to pointer: CGPoint) {
        guard let session else { return }
        self.pointer = pointer
        location = CGPoint(x: pointer.x - session.grabOffset.width, y: pointer.y - session.grabOffset.height)
        if session.isInFolder {
            guard let folder, folder.frames.card.contains(pointer) else {
                if leaveFolderCard() {
                    move(to: pointer)
                }
                return
            }
            if let slot = folderSlot(for: location) {
                retargetAfterDwell(slot)
            }
            return
        }
        updateEdge()
        // A flip may have moved the session to another page.
        guard let session = self.session else { return }
        if updateMerge(session) { return }
        guard let slot = dropSlot(for: location, session: session) else { return }
        retargetAfterDwell(slot)
    }

    private func retargetAfterDwell(_ slot: Int) {
        guard let session else { return }
        if slot == session.targetSlot {
            cancelDwell()
            return
        }
        guard slot != pendingSlot else { return }
        cancelDwell()
        pendingSlot = slot
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Drag.dwell))
            guard !Task.isCancelled, let self else { return }
            self.pendingSlot = nil
            self.dwellTask = nil
            withAnimation(Self.animation) {
                self.session?.retarget(slot)
            }
        }
    }

    // While the lifted app rests on the middle of another icon the reflow
    // pauses; after `Drag.mergeDwell` that icon becomes the merge target.
    // Returns true while over such a middle.
    private func updateMerge(_ session: DragSession) -> Bool {
        guard let target = mergeTarget(for: location, session: session) else {
            cancelMergeDwell()
            if session.mergeTargetID != nil {
                withAnimation(Self.animation) {
                    self.session?.setMergeTarget(nil)
                }
            }
            return false
        }
        cancelDwell()
        guard target != session.mergeTargetID, target != pendingMerge else { return true }
        cancelMergeDwell()
        if session.mergeTargetID != nil {
            withAnimation(Self.animation) {
                self.session?.setMergeTarget(nil)
            }
        }
        pendingMerge = target
        mergeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Drag.mergeDwell))
            guard !Task.isCancelled, let self else { return }
            self.pendingMerge = nil
            self.mergeTask = nil
            withAnimation(Self.animation) {
                self.session?.setMergeTarget(target)
            }
        }
        return true
    }

    // The icon whose merge zone is under the lifted icon's center, as the
    // page shows it now. Only apps merge; folders are never merged into
    // anything (no folder in a folder).
    private func mergeTarget(for center: CGPoint, session: DragSession) -> String? {
        guard case .app = session.item, let grid, let lifted = liftedItem,
              grid.pages.indices.contains(session.page) || session.insertsItem else { return nil }
        let items = self.items(onPage: session.page, of: grid, for: session)
        let shown = session.preview(items, page: session.page, moved: lifted, capacity: grid.geometry.capacity)
        guard let slot = grid.geometry.mergeSlot(at: center - grid.frame.origin, itemCount: shown.count) else { return nil }
        let target = shown[slot].id
        return target == session.itemID ? nil : target
    }

    // The app left the folder card: close the folder and carry the app over
    // the grid page under it.
    // Returns false when there is no grid to carry it over.
    @discardableResult
    private func leaveFolderCard() -> Bool {
        guard var session, session.isInFolder, let grid else { return false }
        cancelDwell()
        folder = nil
        leaveFolder()
        let tile = session.sourceFolderID.flatMap { folderID in
            grid.pages.indices.lazy.compactMap { page in
                self.items(onPage: page, of: grid, for: session).firstIndex { $0.id == folderID }.map { (page: page, slot: $0) }
            }.first
        }
        let page = grid.page
        session.leaveFolder(
            tilePage: tile?.page ?? page,
            tileSlot: tile?.slot ?? items(onPage: page, of: grid, for: session).count,
            page: page,
            slot: 0
        )
        if let slot = dropSlot(for: location, session: session) {
            session.retarget(slot)
        }
        withAnimation(Self.animation) {
            self.session = session
        }
        return true
    }

    // Flips the page when the pointer has rested in an edge zone long enough,
    // and wakes up again when the next flip is due, since a still pointer
    // sends no events.
    private func updateEdge() {
        edgeTask?.cancel()
        edgeTask = nil
        guard phase == .dragging, session?.isInFolder == false, let grid else { return }
        let now = clock()
        if let direction = edge.update(direction: grid.geometry.edgeDirection(at: pointer - grid.frame.origin), now: now) {
            flip(direction)
        }
        guard let deadline = edge.deadline else { return }
        edgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(deadline - now, 0)))
            guard !Task.isCancelled, let self else { return }
            self.updateEdge()
        }
    }

    private func flip(_ direction: Int) {
        guard var session, !session.isDropping, let page = flipPage(direction), page != session.page else { return }
        cancelDwell()
        cancelMergeDwell()
        session.switchPage(to: page, slot: 0)
        if let slot = dropSlot(for: location, session: session) {
            session.switchPage(to: page, slot: slot)
        }
        withAnimation(Self.animation) {
            self.session = session
        }
    }

    // Slot under the lifted icon's center (not the raw pointer, so grabbing an
    // icon by its edge doesn't skew the target). On a page the item is
    // carried to, the slot past the last item is a target too.
    private func dropSlot(for center: CGPoint, session: DragSession) -> Int? {
        guard let grid else { return nil }
        let count = items(onPage: session.page, of: grid, for: session).count
        return grid.geometry.dropSlot(at: center - grid.frame.origin, itemCount: session.insertsItem ? count + 1 : count)
    }

    // Index in the open folder under the lifted icon's center, on the folder
    // page shown.
    private func folderSlot(for center: CGPoint) -> Int? {
        guard let folder else { return nil }
        let count = folderPageCount(folder, appCount: session.map { $0.lifting(folder.apps).count } ?? folder.apps.count)
        guard count > 0 else { return nil }
        let slot = folder.geometry.dropSlot(at: center - folder.frames.grid.origin, itemCount: count)
        return folder.page * FolderGrid.appsPerPage + slot
    }

    // Apps on the folder page shown, out of `appCount` in the folder.
    private func folderPageCount(_ folder: FolderContext, appCount: Int) -> Int {
        min(max(appCount - folder.page * FolderGrid.appsPerPage, 0), FolderGrid.appsPerPage)
    }

    // A grid drag whose item is no longer where it started (a rescan moved
    // it) must not be committed.
    private func isValid(_ session: DragSession) -> Bool {
        guard session.sourceFolderID == nil else { return true }
        guard let grid else { return false }
        let items = self.items(onPage: session.sourcePage, of: grid, for: session)
        return items.indices.contains(session.sourceSlot) && items[session.sourceSlot].id == session.itemID
    }

    // Flies the lifted icon into its cell (shrinking into a merge target),
    // then removes it and reveals the real cell underneath.
    private func land(_ dropped: DragSession) {
        var target = location
        if dropped.isInFolder, let folder {
            let cell = folder.geometry.cellFrame(slot: dropped.targetSlot - folder.page * FolderGrid.appsPerPage)
            target = CGPoint(x: cell.midX, y: cell.midY) + folder.frames.grid.origin
        } else if let grid {
            let cell = grid.geometry.cellFrame(slot: dropped.targetSlot)
            target = CGPoint(x: cell.midX, y: cell.midY) + grid.frame.origin
        }
        withAnimation(Self.animation) {
            session = dropped
            location = target
        } completion: { [weak self] in
            guard let self, self.session?.isDropping == true else { return }
            self.session = nil
            self.liftedItem = nil
            self.liftedCompanions = []
        }
    }

    private func finishGesture() {
        phase = .idle
        if marquee != nil {
            marquee = nil
        }
        cancelTimers()
        guard isTapSuppressed else { return }
        // The icon's tap handler runs on the same mouse-up; clear the flag
        // only after it had its chance to see it.
        Task { [weak self] in
            self?.isTapSuppressed = false
        }
    }

    private func cancelTimers() {
        cancelDwell()
        cancelMergeDwell()
        edgeTask?.cancel()
        edgeTask = nil
        edge.reset()
    }

    private func cancelDwell() {
        dwellTask?.cancel()
        dwellTask = nil
        pendingSlot = nil
    }

    private func cancelMergeDwell() {
        mergeTask?.cancel()
        mergeTask = nil
        pendingMerge = nil
    }

    static var animation: Animation? {
        Motion.current.dragAnimation
    }
}

private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}
