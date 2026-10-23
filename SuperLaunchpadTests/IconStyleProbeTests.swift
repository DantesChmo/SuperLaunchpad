import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct IconStyleProbeTests {

    // Hands out the renders in order; nil once they run out.
    private func probe(_ renders: [Data?]) -> IconStyleProbe {
        var remaining = renders
        return IconStyleProbe {
            remaining.isEmpty ? nil : remaining.removeFirst()
        }
    }

    private let light = Data([1])
    private let dark = Data([2])

    @Test func firstCheckOnlyRecords() {
        #expect(probe([light]).styleDidChange() == false)
    }

    @Test func sameRenderIsNoChange() {
        let p = probe([light, light])
        _ = p.styleDidChange()
        #expect(p.styleDidChange() == false)
    }

    @Test func differentRenderIsAChangeOnce() {
        let p = probe([light, dark, dark])
        _ = p.styleDidChange()
        #expect(p.styleDidChange() == true)
        #expect(p.styleDidChange() == false)
    }

    @Test func failedRenderKeepsTheLastStyle() {
        let p = probe([light, nil, dark])
        _ = p.styleDidChange()
        #expect(p.styleDidChange() == false)
        #expect(p.styleDidChange() == true)
    }

    @Test func liveReferenceIconRenders() {
        #expect(IconStyleProbe.renderReferenceIcon() != nil)
    }
}
