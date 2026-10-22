import Foundation
import Testing
@testable import SuperLaunchpad

struct RescanGateTests {

    @Test func firstRequestStartsRescan() {
        var gate = RescanGate()
        #expect(gate.request() == true)
        #expect(gate.isRunning == true)
        #expect(gate.isPending == false)
    }

    @Test func requestWhileRunningIsDeferred() {
        var gate = RescanGate()
        _ = gate.request()
        #expect(gate.request() == false)
        #expect(gate.isPending == true)
    }

    @Test func finishWithoutPendingStops() {
        var gate = RescanGate()
        _ = gate.request()
        #expect(gate.finish() == false)
        #expect(gate.isRunning == false)
    }

    @Test func requestsWhileRunningCoalesceIntoOneFollowUp() {
        var gate = RescanGate()
        _ = gate.request()
        for _ in 0..<5 {
            #expect(gate.request() == false)
        }
        // Exactly one follow-up, which keeps the gate running...
        #expect(gate.finish() == true)
        #expect(gate.isRunning == true)
        #expect(gate.isPending == false)
        // ...and nothing after it.
        #expect(gate.finish() == false)
        #expect(gate.isRunning == false)
    }

    @Test func requestDuringFollowUpSchedulesAnother() {
        var gate = RescanGate()
        _ = gate.request()
        _ = gate.request()
        #expect(gate.finish() == true)
        #expect(gate.request() == false)
        #expect(gate.finish() == true)
        #expect(gate.finish() == false)
    }

    @Test func requestAfterStopStartsAgain() {
        var gate = RescanGate()
        _ = gate.request()
        _ = gate.finish()
        #expect(gate.request() == true)
    }
}
