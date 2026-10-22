import AppKit
import SwiftUI

// Drives drag-to-reorder on the main grid: turns `DragGesture` updates into a
// `DragSession`, debounces slot changes with a short dwell, flips pages while
// the pointer rests beside the grid, and runs the lift / reflow / drop
// animations. The slot math lives in `GridGeometry`.
//
// Observation is split so a mouse move re-renders only the lifted icon:
// `location` changes every event and is read by the overlay alone, while
// `session` (read by the pages) changes only when the target slot does.
//
// Slots are computed for the page the pager settles on (`session.page`), not
// for the mid-flight position, so a target stays put while the pages slide.
@MainActor
@Observable
final class GridDragController {
    private(set) var session: DragSession?
    // The lifted icon's center, in the pager container's coordinates.
    private(set) var location: CGPoint = .zero
    private(set) var liftedItem: LaunchpadItem?

    // A click on an icon that turned into a drag must not also launch it or
    // open its folder. Stays set until just after the drag ends.
    @ObservationIgnored private(set) var isTapSuppressed = false

    // Edge paging: asks the grid to flip by -1 / +1 and returns the page now
    // shown, or nil when it could not flip. Set with every `update`.
    @ObservationIgnored private var flipPage: (Int) -> Int? = { _ in nil }
    private let clock: () -> TimeInterval

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    @ObservationIgnored private var phase = Phase.idle
    @ObservationIgnored private var pages: [[LaunchpadItem]] = []
    @ObservationIgnored private var geometry: GridGeometry?
    @ObservationIgnored private var pointer: CGPoint = .zero
    @ObservationIgnored private var pendingSlot: Int?
    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    @ObservationIgnored private var edge = EdgeDwell()
    @ObservationIgnored private var edgeTask: Task<Void, Never>?

    private enum Phase {
        case idle
        // The press started outside any icon, or the drag was cancelled with
        // Esc; ignore the rest of it.
        case ignored
        case dragging
    }

    var isActive: Bool { session != nil }

    // MARK: - Gesture input

    // Feeds one `DragGesture` change. `start` and `pointer` are in the pager
    // container's coordinates. Returns true when this update lifted an icon.
    @discardableResult
    func update(
        start: CGPoint,
        pointer: CGPoint,
        pages: [[LaunchpadItem]],
        page: Int,
        geometry: GridGeometry,
        pagerPosition: Double,
        pageWidth: CGFloat,
        flipPage: @escaping (Int) -> Int?
    ) -> Bool {
        self.pages = pages
        self.geometry = geometry
        self.flipPage = flipPage
        switch phase {
        case .ignored:
            return false
        case .idle:
            // A drop is still flying home: don't start a second drag on top.
            guard session == nil, pages.indices.contains(page) else {
                phase = .ignored
                return false
            }
            let local = GridGeometry.pageLocal(start, page: page, pagerPosition: pagerPosition, pageWidth: pageWidth)
            guard let slot = geometry.item(at: local, itemCount: pages[page].count) else {
                phase = .ignored
                return false
            }
            let item = pages[page][slot]
            let cell = geometry.cellFrame(slot: slot)
            phase = .dragging
            isTapSuppressed = true
            liftedItem = item
            session = DragSession(
                itemID: item.id,
                item: item.layoutItem,
                page: page,
                slot: slot,
                grabOffset: CGSize(width: local.x - cell.midX, height: local.y - cell.midY)
            )
            move(to: pointer)
            return true
        case .dragging:
            move(to: pointer)
            return false
        }
    }

    // Releases the pointer. `commit` persists the move (the view model's
    // `moveItem`) and returns where the item ended up, or nil when the edit
    // was refused; the lifted icon then flies back to where it came from.
    // Returns the page the icon lands on, for the pager to show.
    @discardableResult
    func end(commit: (DragSession) -> (page: Int, slot: Int)?) -> Int? {
        defer { finishGesture() }
        guard phase == .dragging, var session else { return nil }
        cancelTimers()
        // The drop lands where the pointer is now, dwell or not.
        if let slot = dropSlot(for: location, session: session) {
            session.retarget(slot)
        }
        let isValid = pages.indices.contains(session.sourcePage)
            && pages[session.sourcePage].indices.contains(session.sourceSlot)
            && pages[session.sourcePage][session.sourceSlot].id == session.itemID
        if session.hasMoved, isValid, let landed = commit(session) {
            session.markCommitted(page: landed.page, slot: landed.slot)
        } else {
            session.revert()
        }
        session.beginDrop()
        land(session)
        return session.page
    }

    // Esc while dragging: the icon flies back to its source cell and the rest
    // of the gesture is ignored. Returns the source page, for the pager to
    // show, or nil when no drag was in progress.
    @discardableResult
    func cancelDrop() -> Int? {
        guard phase == .dragging, var session, !session.isDropping else { return nil }
        cancelTimers()
        phase = .ignored
        session.revert()
        session.beginDrop()
        land(session)
        return session.page
    }

    // The gesture went away without a release (panel hidden, view removed):
    // drop everything without persisting or animating.
    func cancel() {
        cancelTimers()
        session = nil
        liftedItem = nil
        finishGesture()
    }

    // MARK: - Private

    private func move(to pointer: CGPoint) {
        guard let session else { return }
        self.pointer = pointer
        location = CGPoint(x: pointer.x - session.grabOffset.width, y: pointer.y - session.grabOffset.height)
        updateEdge()
        // A flip may have moved the session to another page.
        guard let session = self.session, let slot = dropSlot(for: location, session: session) else { return }
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

    // Flips the page when the pointer has rested in an edge zone long enough,
    // and wakes up again when the next flip is due, since a still pointer
    // sends no events.
    private func updateEdge() {
        edgeTask?.cancel()
        edgeTask = nil
        guard phase == .dragging, let geometry else { return }
        let now = clock()
        if let direction = edge.update(direction: geometry.edgeDirection(at: pointer), now: now) {
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
        session.switchPage(to: page, slot: 0)
        if let slot = dropSlot(for: location, session: session) {
            session.switchPage(to: page, slot: slot)
        }
        withAnimation(Self.animation) {
            self.session = session
        }
    }

    // Slot under the lifted icon's center (not the raw pointer, so grabbing an
    // icon by its edge doesn't skew the target). On a page the item was
    // carried to, the slot past the last item is a target too.
    private func dropSlot(for center: CGPoint, session: DragSession) -> Int? {
        guard let geometry else { return nil }
        let count = pages.indices.contains(session.page) ? pages[session.page].count : 0
        return geometry.dropSlot(at: center, itemCount: session.page == session.sourcePage ? count : count + 1)
    }

    // Flies the lifted icon into its cell, then removes it and reveals the
    // real cell underneath.
    private func land(_ dropped: DragSession) {
        guard let geometry else { return }
        let cell = geometry.cellFrame(slot: dropped.targetSlot)
        withAnimation(Self.animation) {
            session = dropped
            location = CGPoint(x: cell.midX, y: cell.midY)
        } completion: { [weak self] in
            guard let self, self.session?.isDropping == true else { return }
            self.session = nil
            self.liftedItem = nil
        }
    }

    private func finishGesture() {
        phase = .idle
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
        edgeTask?.cancel()
        edgeTask = nil
        edge.reset()
    }

    private func cancelDwell() {
        dwellTask?.cancel()
        dwellTask = nil
        pendingSlot = nil
    }

    static var animation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil
            : .spring(duration: Drag.springDuration, bounce: 0)
    }
}
