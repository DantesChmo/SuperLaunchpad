import AppKit
import QuartzCore

// Drives the main-grid pager: turns trackpad / mouse wheel / arrow-key input
// into `PagerModel` updates and runs the settle spring on a display link.
//
// Only `position` and `isPaging` are observed. `position` changes every frame
// but is read solely by the offset modifier in `PagingGridView`, so a frame
// never re-renders the pages. `viewModel.currentPage` is written only when a
// page is decided (release, key press, wheel burst), never per frame.
@Observable
final class PagerController {
    private(set) var position: Double = 0
    private(set) var isPaging = false

    // Set by `PagingGridView` from its measured width.
    @ObservationIgnored var pageWidth: CGFloat = 0

    private let viewModel: LaunchpadViewModel
    @ObservationIgnored private var model = PagerModel(pageCount: 0)
    @ObservationIgnored private var wheel = WheelAccumulator()
    @ObservationIgnored private var gesture = TrackpadGesture.idle
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastFrameTimestamp: CFTimeInterval?

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Input

    func handleScroll(_ event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            handleTrackpad(event)
        } else {
            handleWheel(event)
        }
    }

    func step(by delta: Int) {
        syncPageCount()
        let previous = model.page
        let page = model.step(by: delta)
        guard page != previous else { return }
        commit(page)
        startSettling()
    }

    // Jumps to page 0 without animation. Call while the panel is hidden.
    func reset() {
        stopDisplayLink()
        model.reset()
        wheel = WheelAccumulator()
        gesture = .idle
        publish()
        commit(0)
    }

    func syncPageCount() {
        let previous = model.page
        model.setPageCount(viewModel.pages.count)
        guard model.page != previous else { return }
        commit(model.page)
        startSettling()
    }

    // MARK: - Trackpad

    private func handleTrackpad(_ event: NSEvent) {
        // Momentum after release is ignored: the page was decided on `.ended`
        // and the spring owns the motion from there.
        guard event.momentumPhase.isEmpty else { return }

        if event.phase.contains(.began) {
            gesture = .pending
            decideAxis(with: event)
        } else if event.phase.contains(.changed) {
            switch gesture {
            case .pending: decideAxis(with: event)
            case .dragging: drag(with: event)
            case .idle, .ignored: break
            }
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let wasDragging = gesture == .dragging
            gesture = .idle
            guard wasDragging else { return }
            let page = model.endDrag(timestamp: event.timestamp)
            commit(page)
            startSettling()
        }
    }

    // The first movement decides the gesture: mostly vertical two-finger
    // scrolls are ignored so they don't grab the grid.
    private func decideAxis(with event: NSEvent) {
        let dx = abs(event.scrollingDeltaX)
        let dy = abs(event.scrollingDeltaY)
        guard dx > 0 || dy > 0 else { return }
        guard dx >= dy else {
            gesture = .ignored
            return
        }
        syncPageCount()
        stopDisplayLink()
        model.beginDrag(timestamp: event.timestamp)
        gesture = .dragging
        drag(with: event)
    }

    private func drag(with event: NSEvent) {
        guard pageWidth > 0 else { return }
        // Fingers right (positive delta) reveal the previous page.
        model.drag(by: -Double(event.scrollingDeltaX / pageWidth), timestamp: event.timestamp)
        publish()
    }

    // MARK: - Mouse wheel

    private func handleWheel(_ event: NSEvent) {
        // Tilting wheels report horizontal deltas; use the dominant axis.
        // Wheel down / right → next page.
        let towardsNext = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? -event.scrollingDeltaX
            : event.scrollingDeltaY
        guard let direction = wheel.consume(delta: Double(towardsNext), timestamp: event.timestamp) else { return }
        step(by: direction)
    }

    // MARK: - Settling

    private func commit(_ page: Int) {
        if viewModel.currentPage != page {
            viewModel.currentPage = page
        }
    }

    private func startSettling() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            model.settleImmediately()
        }
        publish()
        guard model.isSettling else {
            stopDisplayLink()
            return
        }
        startDisplayLink()
    }

    private func publish() {
        if position != model.position {
            position = model.position
        }
        if isPaging != model.isPaging {
            isPaging = model.isPaging
        }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = now - (lastFrameTimestamp ?? link.timestamp)
        lastFrameTimestamp = now
        model.advance(by: dt)
        publish()
        if !model.isSettling {
            stopDisplayLink()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        guard let screen = NSScreen.main else {
            model.settleImmediately()
            publish()
            return
        }
        let link = screen.displayLink(target: DisplayLinkTarget(owner: self), selector: #selector(DisplayLinkTarget.tick(_:)))
        lastFrameTimestamp = nil
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = nil
    }
}

private enum TrackpadGesture {
    case idle
    // Fingers are down but haven't moved yet.
    case pending
    case dragging
    case ignored
}

// The display link retains its target; this proxy holds the controller weakly
// so an invalidated-late link can't keep it alive.
private final class DisplayLinkTarget: NSObject {
    private weak var owner: PagerController?

    init(owner: PagerController) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        owner?.tick(link)
    }
}
