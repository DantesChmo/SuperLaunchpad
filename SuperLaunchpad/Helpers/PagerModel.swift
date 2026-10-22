import Foundation

// Pure paging physics for the main grid: 1:1 drag with rubber-banding, the
// release decision (offset + flick velocity, at most one page per swipe) and a
// critically damped spring that keeps its velocity when retargeted.
//
// All positions are in pages (1.3 = 30% of the way from page 1 to page 2) and
// velocities in pages per second. No AppKit/SwiftUI here so it can be unit
// tested; `PagerController` feeds it events and display-link ticks.
struct PagerModel {
    private(set) var pageCount: Int
    // The decided page: where the pager rests or is settling towards.
    private(set) var page = 0
    // What is on screen right now.
    private(set) var position: Double = 0
    private(set) var velocity: Double = 0
    private(set) var isDragging = false
    private(set) var isSettling = false

    // Finger position without rubber-banding applied.
    private var rawPosition: Double = 0
    private var dragAnchorPage = 0
    private var lastDragTimestamp: TimeInterval?

    var isPaging: Bool { isDragging || isSettling }

    private var lastPage: Int { max(pageCount - 1, 0) }

    init(pageCount: Int) {
        self.pageCount = max(pageCount, 0)
    }

    // MARK: - Lifecycle

    mutating func reset() {
        page = 0
        position = 0
        velocity = 0
        rawPosition = 0
        isDragging = false
        isSettling = false
        lastDragTimestamp = nil
    }

    mutating func setPageCount(_ count: Int) {
        pageCount = max(count, 0)
        guard page > lastPage else { return }
        page = lastPage
        if !isDragging {
            isSettling = true
        }
    }

    // MARK: - Drag

    mutating func beginDrag(timestamp: TimeInterval) {
        isDragging = true
        isSettling = false
        velocity = 0
        dragAnchorPage = page
        rawPosition = Self.unbounded(position, lastPage: lastPage)
        lastDragTimestamp = timestamp
    }

    mutating func drag(by deltaPages: Double, timestamp: TimeInterval) {
        guard isDragging else { return }
        rawPosition += deltaPages
        let newPosition = Self.bounded(rawPosition, lastPage: lastPage)
        if let last = lastDragTimestamp, timestamp > last {
            let instant = (newPosition - position) / (timestamp - last)
            velocity += (instant - velocity) * Paging.velocitySmoothing
        }
        position = newPosition
        lastDragTimestamp = timestamp
    }

    // Returns the decided page.
    @discardableResult
    mutating func endDrag(timestamp: TimeInterval) -> Int {
        guard isDragging else { return page }
        if let last = lastDragTimestamp, timestamp - last > Paging.velocityStaleInterval {
            velocity = 0
        }
        isDragging = false
        page = Self.targetPage(position: position, velocity: velocity, anchor: dragAnchorPage, pageCount: pageCount)
        isSettling = true
        return page
    }

    // MARK: - Discrete steps (keys, mouse wheel)

    // Moves the decided page by `delta` from the current target, not from the
    // on-screen position, so rapid presses queue up and retarget the running
    // spring instead of restarting it.
    @discardableResult
    mutating func step(by delta: Int) -> Int {
        guard !isDragging else { return page }
        let newPage = min(max(page + delta, 0), lastPage)
        guard newPage != page else { return page }
        page = newPage
        isSettling = true
        return page
    }

    // MARK: - Settling

    mutating func advance(by dt: Double) {
        guard isSettling else { return }
        let target = Double(page)
        let next = Self.spring(displacement: position - target, velocity: velocity, dt: dt)
        position = target + next.displacement
        velocity = next.velocity
        if abs(next.displacement) < Paging.settleDistance, abs(next.velocity) < Paging.settleVelocity {
            settleImmediately()
        }
    }

    mutating func settleImmediately() {
        guard !isDragging else { return }
        position = Double(page)
        velocity = 0
        isSettling = false
    }

    // MARK: - Pure functions

    static func targetPage(position: Double, velocity: Double, anchor: Int, pageCount: Int) -> Int {
        let lastPage = max(pageCount - 1, 0)
        let proposed: Double
        if velocity > Paging.flickVelocity {
            proposed = position.rounded(.down) + 1
        } else if velocity < -Paging.flickVelocity {
            proposed = position.rounded(.up) - 1
        } else {
            proposed = position.rounded()
        }
        let lower = max(anchor - 1, 0)
        let upper = min(anchor + 1, lastPage)
        return min(max(Int(proposed), lower), max(upper, lower))
    }

    // Maps an unbounded overshoot (in pages) to a damped one that approaches
    // but never reaches one page.
    static func rubberBand(_ overshoot: Double) -> Double {
        let magnitude = 1 - 1 / (abs(overshoot) * Paging.rubberBandCoefficient + 1)
        return overshoot < 0 ? -magnitude : magnitude
    }

    static func inverseRubberBand(_ banded: Double) -> Double {
        let magnitude = min(abs(banded), Paging.rubberBandInverseLimit)
        let raw = (1 / (1 - magnitude) - 1) / Paging.rubberBandCoefficient
        return banded < 0 ? -raw : raw
    }

    static func bounded(_ raw: Double, lastPage: Int) -> Double {
        let upper = Double(lastPage)
        if raw < 0 { return rubberBand(raw) }
        if raw > upper { return upper + rubberBand(raw - upper) }
        return raw
    }

    static func unbounded(_ position: Double, lastPage: Int) -> Double {
        let upper = Double(lastPage)
        if position < 0 { return inverseRubberBand(position) }
        if position > upper { return upper + inverseRubberBand(position - upper) }
        return position
    }

    // Closed-form critically damped spring, exact for any `dt`, so stepping
    // per display frame never drifts and retargeting keeps the velocity.
    static func spring(displacement x0: Double, velocity v0: Double, dt: Double) -> (displacement: Double, velocity: Double) {
        let omega = 2 * Double.pi / Paging.springResponse
        let b = v0 + omega * x0
        let decay = exp(-omega * dt)
        return ((x0 + b * dt) * decay, (v0 - omega * b * dt) * decay)
    }
}

// Turns a mouse wheel (discrete ticks, no phases) into one page step per burst
// of ticks; the burst ends once ticks stop for `Paging.wheelBurstGap`.
struct WheelAccumulator {
    private var accumulated: Double = 0
    private var lastTimestamp: TimeInterval?
    private var hasFired = false

    // `delta` > 0 means "towards the next page". Returns +1 / -1 when this
    // tick completes a page step, otherwise nil.
    mutating func consume(delta: Double, timestamp: TimeInterval) -> Int? {
        let isSameBurst = lastTimestamp.map { timestamp - $0 <= Paging.wheelBurstGap } ?? false
        if !isSameBurst {
            accumulated = 0
            hasFired = false
        }
        lastTimestamp = timestamp
        guard !hasFired else { return nil }
        accumulated += delta
        guard abs(accumulated) >= Paging.wheelThreshold else { return nil }
        hasFired = true
        return accumulated > 0 ? 1 : -1
    }
}
