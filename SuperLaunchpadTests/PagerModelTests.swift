import Foundation
import Testing
@testable import SuperLaunchpad

struct PagerModelTests {

    private let tolerance = 1e-9

    // Runs the settle spring until it stops (or a generous frame budget runs out).
    private func settle(_ model: inout PagerModel) {
        for _ in 0..<600 where model.isSettling {
            model.advance(by: 1.0 / 120)
        }
    }

    // MARK: - Target page

    @Test(arguments: [
        // (position, velocity, anchor, expected)
        (0.2, 0.0, 0, 0),
        (0.6, 0.0, 0, 1),
        (0.2, 2.0, 0, 1),
        (0.8, -2.0, 0, 0),
        (1.0, 2.0, 1, 2),
        (1.0, -2.0, 1, 0),
        (1.6, -2.0, 1, 1),
    ])
    func targetPageUsesOffsetAndFlick(position: Double, velocity: Double, anchor: Int, expected: Int) {
        #expect(PagerModel.targetPage(position: position, velocity: velocity, anchor: anchor, pageCount: 5) == expected)
    }

    @Test func targetPageMovesAtMostOnePagePerSwipe() {
        #expect(PagerModel.targetPage(position: 3.4, velocity: 0, anchor: 1, pageCount: 5) == 2)
        #expect(PagerModel.targetPage(position: 0, velocity: -50, anchor: 3, pageCount: 5) == 2)
    }

    @Test func targetPageStaysInBounds() {
        #expect(PagerModel.targetPage(position: -0.4, velocity: -5, anchor: 0, pageCount: 3) == 0)
        #expect(PagerModel.targetPage(position: 2.4, velocity: 5, anchor: 2, pageCount: 3) == 2)
        #expect(PagerModel.targetPage(position: 0.3, velocity: 5, anchor: 0, pageCount: 1) == 0)
        #expect(PagerModel.targetPage(position: 0, velocity: 5, anchor: 0, pageCount: 0) == 0)
    }

    // MARK: - Rubber band

    @Test func rubberBandIsZeroAtRestAndDampedBeyond() {
        #expect(PagerModel.rubberBand(0) == 0)
        let small = PagerModel.rubberBand(0.1)
        let large = PagerModel.rubberBand(10)
        #expect(small > 0 && small < 0.1)
        #expect(large > small && large < 1)
        #expect(PagerModel.rubberBand(-0.3) == -PagerModel.rubberBand(0.3))
    }

    @Test(arguments: [-2.0, -0.3, 0.0, 0.05, 0.7, 3.0])
    func inverseRubberBandRoundTrips(overshoot: Double) {
        let banded = PagerModel.rubberBand(overshoot)
        #expect(abs(PagerModel.inverseRubberBand(banded) - overshoot) < 1e-6)
    }

    @Test func boundedLeavesInRangePositionsUntouched() {
        #expect(PagerModel.bounded(1.3, lastPage: 3) == 1.3)
        #expect(PagerModel.bounded(-0.5, lastPage: 3) > -0.5)
        #expect(PagerModel.bounded(3.5, lastPage: 3) < 3.5)
        #expect(PagerModel.bounded(3.5, lastPage: 3) > 3)
    }

    // MARK: - Spring

    @Test func springStepsComposeExactly() {
        let whole = PagerModel.spring(displacement: 1, velocity: -3, dt: 0.05)
        let half = PagerModel.spring(displacement: 1, velocity: -3, dt: 0.025)
        let twice = PagerModel.spring(displacement: half.displacement, velocity: half.velocity, dt: 0.025)
        #expect(abs(whole.displacement - twice.displacement) < tolerance)
        #expect(abs(whole.velocity - twice.velocity) < tolerance)
    }

    @Test func springConverges() {
        let end = PagerModel.spring(displacement: 1, velocity: 4, dt: 2)
        #expect(abs(end.displacement) < Paging.settleDistance)
        #expect(abs(end.velocity) < Paging.settleVelocity)
    }

    // MARK: - Drag

    @Test func dragTracksFingersOneToOne() {
        var model = PagerModel(pageCount: 3)
        model.beginDrag(timestamp: 0)
        model.drag(by: 0.25, timestamp: 0.01)
        model.drag(by: 0.1, timestamp: 0.02)
        #expect(abs(model.position - 0.35) < tolerance)
        #expect(model.isDragging)
        #expect(model.isPaging)
    }

    @Test func dragRubberBandsAtFirstAndLastPage() {
        var model = PagerModel(pageCount: 2)
        model.beginDrag(timestamp: 0)
        model.drag(by: -0.5, timestamp: 0.01)
        #expect(model.position < 0 && model.position > -0.5)

        model.drag(by: 2.0, timestamp: 0.02)
        #expect(model.position > 1 && model.position < 1.5)
    }

    @Test func slowShortDragSnapsBack() {
        var model = PagerModel(pageCount: 3)
        model.beginDrag(timestamp: 0)
        model.drag(by: 0.2, timestamp: 0.1)
        #expect(model.endDrag(timestamp: 0.5) == 0)
        settle(&model)
        #expect(model.position == 0)
        #expect(!model.isPaging)
    }

    @Test func flickAdvancesOnePage() {
        var model = PagerModel(pageCount: 3)
        model.beginDrag(timestamp: 0)
        model.drag(by: 0.05, timestamp: 0.01)
        model.drag(by: 0.05, timestamp: 0.02)
        #expect(model.endDrag(timestamp: 0.025) == 1)
        #expect(model.velocity > 0)
    }

    @Test func pausedFingersBeforeReleaseAreNotAFlick() {
        var model = PagerModel(pageCount: 3)
        model.beginDrag(timestamp: 0)
        model.drag(by: 0.05, timestamp: 0.01)
        model.drag(by: 0.05, timestamp: 0.02)
        #expect(model.endDrag(timestamp: 0.02 + Paging.velocityStaleInterval * 2) == 0)
    }

    @Test func releaseSpringStartsFromFingerVelocity() {
        var model = PagerModel(pageCount: 3)
        model.beginDrag(timestamp: 0)
        model.drag(by: 0.3, timestamp: 0.05)
        model.drag(by: 0.3, timestamp: 0.1)
        model.endDrag(timestamp: 0.1)
        let releaseVelocity = model.velocity
        let before = model.position
        model.advance(by: 0.001)
        #expect(releaseVelocity > 0)
        #expect(model.position > before)
    }

    @Test func catchingASettlingPageKeepsItsPosition() {
        var model = PagerModel(pageCount: 3)
        model.step(by: 1)
        model.advance(by: 0.05)
        let caught = model.position
        model.beginDrag(timestamp: 1)
        #expect(model.position == caught)
        #expect(!model.isSettling)
        model.drag(by: 0, timestamp: 1.01)
        #expect(abs(model.position - caught) < tolerance)
    }

    @Test func catchingInsideTheRubberBandDoesNotJump() {
        var model = PagerModel(pageCount: 2)
        model.beginDrag(timestamp: 0)
        model.drag(by: -0.4, timestamp: 0.01)
        model.endDrag(timestamp: 0.01)
        model.advance(by: 0.02)
        let caught = model.position
        #expect(caught < 0)
        model.beginDrag(timestamp: 1)
        model.drag(by: 0, timestamp: 1.01)
        #expect(abs(model.position - caught) < 1e-6)
    }

    // MARK: - Steps

    @Test func rapidStepsRetargetWithoutLosingVelocity() {
        var model = PagerModel(pageCount: 5)
        model.step(by: 1)
        model.advance(by: 0.05)
        let velocity = model.velocity
        let position = model.position
        #expect(model.step(by: 1) == 2)
        #expect(model.velocity == velocity)
        #expect(model.position == position)
        settle(&model)
        #expect(model.position == 2)
    }

    @Test func stepsClampToPageRange() {
        var model = PagerModel(pageCount: 2)
        #expect(model.step(by: -1) == 0)
        #expect(!model.isSettling)
        #expect(model.step(by: 1) == 1)
        #expect(model.step(by: 1) == 1)
    }

    @Test func stepsAreIgnoredWhileDragging() {
        var model = PagerModel(pageCount: 3)
        model.beginDrag(timestamp: 0)
        #expect(model.step(by: 1) == 0)
    }

    @Test func settleImmediatelyJumpsToTarget() {
        var model = PagerModel(pageCount: 3)
        model.step(by: 1)
        model.settleImmediately()
        #expect(model.position == 1)
        #expect(!model.isPaging)
    }

    @Test func shrinkingPageCountMovesBackInRange() {
        var model = PagerModel(pageCount: 3)
        model.step(by: 2)
        settle(&model)
        model.setPageCount(2)
        #expect(model.page == 1)
        settle(&model)
        #expect(model.position == 1)
    }

    @Test func resetReturnsToFirstPageAtRest() {
        var model = PagerModel(pageCount: 3)
        model.step(by: 2)
        model.advance(by: 0.05)
        model.reset()
        #expect(model.page == 0)
        #expect(model.position == 0)
        #expect(!model.isPaging)
    }
}

struct WheelAccumulatorTests {

    @Test func firstTickOfABurstStepsOnePage() {
        var wheel = WheelAccumulator()
        #expect(wheel.consume(delta: 1, timestamp: 0) == 1)
    }

    @Test func restOfTheBurstIsSwallowed() {
        var wheel = WheelAccumulator()
        #expect(wheel.consume(delta: -1, timestamp: 0) == -1)
        #expect(wheel.consume(delta: -3, timestamp: 0.03) == nil)
        #expect(wheel.consume(delta: -3, timestamp: 0.06) == nil)
    }

    @Test func newBurstAfterAGapStepsAgain() {
        var wheel = WheelAccumulator()
        #expect(wheel.consume(delta: 1, timestamp: 0) == 1)
        #expect(wheel.consume(delta: 1, timestamp: Paging.wheelBurstGap * 2) == 1)
    }

    @Test func smallDeltasAccumulateWithinABurst() {
        var wheel = WheelAccumulator()
        let fraction = Paging.wheelThreshold * 0.6
        #expect(wheel.consume(delta: fraction, timestamp: 0) == nil)
        #expect(wheel.consume(delta: fraction, timestamp: 0.01) == 1)
    }
}
