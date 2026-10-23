import AppKit
import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct IconCacheTests {

    // A fresh cache per test — never share `IconCache.shared` between tests.
    private func makeCache() -> IconCache {
        IconCache()
    }

    // Solid-color PNG of the given pixel size. Different sizes give different
    // byte counts, so the fingerprint is guaranteed to change.
    private func png(side: Int, color: NSColor = NSColor(deviceRed: 0, green: 0.4, blue: 1, alpha: 1)) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        for x in 0..<side {
            for y in 0..<side {
                rep.setColor(color, atX: x, y: y)
            }
        }
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private func app(_ id: String = "com.test.app", iconData: Data?) -> AppEntry {
        AppEntry(
            bundleIdentifier: id,
            displayName: "Test",
            appPath: "/Applications/Test.app",
            iconData: iconData
        )
    }

    @Test func hitReturnsSameInstance() throws {
        let cache = makeCache()
        let entry = app(iconData: try png(side: 16))

        let first = try #require(cache.image(for: entry))
        let second = try #require(cache.image(for: entry))

        #expect(first === second)
    }

    @Test func changedIconDataInvalidatesEntry() throws {
        let cache = makeCache()
        let first = try #require(cache.image(for: app(iconData: try png(side: 16))))
        let second = try #require(cache.image(for: app(iconData: try png(side: 32))))

        #expect(first !== second)
        #expect(second.size.width == 32)
    }

    // Migration v7 clears the old 128 px icons and the rescan stores 256 px
    // ones: the cache must not keep serving the old image meanwhile or after.
    @Test func clearedThenRebuiltIconReplacesOldImage() throws {
        let cache = makeCache()
        let old = try #require(cache.image(for: app(iconData: try png(side: 128))))

        #expect(cache.image(for: app(iconData: nil)) == nil)
        let rebuilt = try #require(cache.image(for: app(iconData: try png(side: AppIcon.pixelSize))))

        #expect(rebuilt !== old)
        #expect(rebuilt.size.width == CGFloat(AppIcon.pixelSize))
    }

    @Test func nilDataReturnsNil() throws {
        let cache = makeCache()
        _ = cache.image(for: app(iconData: try png(side: 16)))

        #expect(cache.image(for: app(iconData: nil)) == nil)
    }

    @Test func undecodableDataReturnsNil() {
        let cache = makeCache()
        #expect(cache.image(for: app(iconData: Data([0x00, 0x01, 0x02]))) == nil)
    }

    @Test func entriesAreKeyedByBundleIdentifier() throws {
        let cache = makeCache()
        let data = try png(side: 16)

        let a = try #require(cache.image(for: app("com.test.a", iconData: data)))
        let b = try #require(cache.image(for: app("com.test.b", iconData: data)))

        #expect(a !== b)
    }

    @Test func prewarmFillsCache() async throws {
        let cache = makeCache()
        let entry = app(iconData: try png(side: 16))

        await cache.prewarm([entry])
        #expect(cache.containsCurrentIcon(for: entry))
        let first = try #require(cache.image(for: entry))
        await cache.prewarm([entry])
        let second = try #require(cache.image(for: entry))

        #expect(first === second)
    }

    @Test func prewarmReplacesStaleEntry() async throws {
        let cache = makeCache()
        let stale = try #require(cache.image(for: app(iconData: try png(side: 16))))
        let updated = app(iconData: try png(side: 32))
        #expect(!cache.containsCurrentIcon(for: updated))

        await cache.prewarm([updated])

        #expect(cache.containsCurrentIcon(for: updated))
        let fresh = try #require(cache.image(for: updated))
        #expect(fresh !== stale)
        #expect(fresh.size.width == 32)
    }
}
