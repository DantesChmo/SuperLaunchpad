import AppKit
import SwiftUI

// Drives drag-to-reorder on the main grid: turns `DragGesture` updates into a
// `DragSession`, debounces slot changes with a short dwell, and runs the
// lift / reflow / drop animations. The slot math lives in `GridGeometry`.
//
// Observation is split so a mouse move re-renders only the lifted icon:
// `location` changes every event and is read by the overlay alone, while
// `session` (read by the pages) changes only when the target slot does.
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

    @ObservationIgnored private var phase = Phase.idle
    @ObservationIgnored private var pendingSlot: Int?
    @ObservationIgnored private var dwellTask: Task<Void, Never>?

    private enum Phase {
        case idle
        // The press started outside any icon; ignore the rest of it.
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
        pageWidth: CGFloat
    ) -> Bool {
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
            move(to: pointer, pages: pages, geometry: geometry, pagerPosition: pagerPosition, pageWidth: pageWidth)
            return true
        case .dragging:
            move(to: pointer, pages: pages, geometry: geometry, pagerPosition: pagerPosition, pageWidth: pageWidth)
            return false
        }
    }

    // Releases the pointer. `commit` persists the move (the view model's
    // `moveItem`) and returns false when the edit was refused; the lifted icon
    // then flies back to where it came from.
    func end(
        pages: [[LaunchpadItem]],
        geometry: GridGeometry,
        pagerPosition: Double,
        pageWidth: CGFloat,
        commit: (DragSession) -> Bool
    ) {
        defer { finishGesture() }
        guard phase == .dragging, var session else { return }
        cancelDwell()
        // The drop lands where the pointer is now, dwell or not.
        if let slot = dropSlot(for: location, session: session, pages: pages, geometry: geometry, pagerPosition: pagerPosition, pageWidth: pageWidth) {
            session.retarget(slot)
        }
        let isValid = pages.indices.contains(session.page)
            && pages[session.page].indices.contains(session.sourceSlot)
            && pages[session.page][session.sourceSlot].id == session.itemID
        if session.hasMoved, isValid, commit(session) {
            session.markCommitted()
        } else {
            session.revert()
        }
        session.beginDrop()
        land(session, geometry: geometry, pagerPosition: pagerPosition, pageWidth: pageWidth)
    }

    // The gesture went away without a release (panel hidden, view removed):
    // drop everything without persisting or animating.
    func cancel() {
        cancelDwell()
        session = nil
        liftedItem = nil
        finishGesture()
    }

    // MARK: - Private

    private func move(to pointer: CGPoint, pages: [[LaunchpadItem]], geometry: GridGeometry, pagerPosition: Double, pageWidth: CGFloat) {
        guard let session else { return }
        location = CGPoint(x: pointer.x - session.grabOffset.width, y: pointer.y - session.grabOffset.height)
        guard let slot = dropSlot(for: location, session: session, pages: pages, geometry: geometry, pagerPosition: pagerPosition, pageWidth: pageWidth) else { return }
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

    // Slot under the lifted icon's center (not the raw pointer, so grabbing an
    // icon by its edge doesn't skew the target).
    private func dropSlot(for center: CGPoint, session: DragSession, pages: [[LaunchpadItem]], geometry: GridGeometry, pagerPosition: Double, pageWidth: CGFloat) -> Int? {
        guard pages.indices.contains(session.page) else { return nil }
        let local = GridGeometry.pageLocal(center, page: session.page, pagerPosition: pagerPosition, pageWidth: pageWidth)
        return geometry.dropSlot(at: local, itemCount: pages[session.page].count)
    }

    // Flies the lifted icon into its cell, then removes it and reveals the
    // real cell underneath.
    private func land(_ dropped: DragSession, geometry: GridGeometry, pagerPosition: Double, pageWidth: CGFloat) {
        let cell = geometry.cellFrame(slot: dropped.targetSlot)
        let home = GridGeometry.containerPoint(CGPoint(x: cell.midX, y: cell.midY), page: dropped.page, pagerPosition: pagerPosition, pageWidth: pageWidth)
        withAnimation(Self.animation) {
            session = dropped
            location = home
        } completion: { [weak self] in
            guard let self, self.session?.isDropping == true else { return }
            self.session = nil
            self.liftedItem = nil
        }
    }

    private func finishGesture() {
        phase = .idle
        cancelDwell()
        guard isTapSuppressed else { return }
        // The icon's tap handler runs on the same mouse-up; clear the flag
        // only after it had its chance to see it.
        Task { [weak self] in
            self?.isTapSuppressed = false
        }
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
