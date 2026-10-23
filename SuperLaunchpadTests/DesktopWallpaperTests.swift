import AppKit
import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct DesktopWallpaperTests {

    // Records what the wallpaper asked for. Images are 1 px high and as wide
    // as the URL's file name is long, so a test can tell which one it got.
    private final class FakeScreens: @unchecked Sendable {
        var urls: [UInt32: URL] = [:]
        var failing: Set<URL> = []
        private let lock = NSLock()
        private var _loads: [(URL, Double)] = []

        var loads: [(URL, Double)] {
            lock.withLock { _loads }
        }

        var provider: DesktopWallpaper.Provider {
            DesktopWallpaper.Provider(
                imageURL: { [unowned self] id in self.urls[id] },
                loadImage: { [unowned self] url, blur in
                    self.lock.withLock { self._loads.append((url, blur)) }
                    guard !self.failing.contains(url) else { return nil }
                    return DesktopWallpaperTests.image(width: url.lastPathComponent.count)
                }
            )
        }
    }

    nonisolated static func image(width: Int) -> CGImage? {
        CGContext(
            data: nil,
            width: width,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }

    private let mainURL = URL(fileURLWithPath: "/pictures/a.heic")
    private let otherURL = URL(fileURLWithPath: "/pictures/longer-name.jpg")

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "DesktopWallpaperTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    private func makeWallpaper(_ screens: FakeScreens, defaults: UserDefaults, style: BackgroundStyle) -> DesktopWallpaper {
        let wallpaper = DesktopWallpaper(provider: screens.provider)
        wallpaper.preferences = Preferences(defaults: defaults)
        wallpaper.preferences.backgroundStyle = style
        return wallpaper
    }

    // MARK: - Source selection

    @Test func desktopStyleAlwaysShowsTheDesktop() {
        #expect(DesktopWallpaper.source(style: .desktop, wallpaperURL: mainURL) == .desktop)
        #expect(DesktopWallpaper.source(style: .desktop, wallpaperURL: nil) == .desktop)
    }

    @Test func wallpaperStyleShowsTheScreensPicture() {
        #expect(DesktopWallpaper.source(style: .wallpaper, wallpaperURL: mainURL) == .wallpaper(mainURL))
    }

    @Test func wallpaperStyleWithoutAPictureFallsBackToTheDesktop() {
        #expect(DesktopWallpaper.source(style: .wallpaper, wallpaperURL: nil) == .desktop)
    }

    // MARK: - Loading

    @Test func desktopStyleLoadsNothing() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        screens.urls[1] = mainURL
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .desktop)

        let load = wallpaper.refresh(displayID: 1)

        #expect(load == nil)
        #expect(wallpaper.image == nil)
        #expect(screens.loads.isEmpty)
    }

    @Test func wallpaperStyleLoadsThePictureOfTheLaunchersScreen() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        screens.urls[1] = mainURL
        screens.urls[2] = otherURL
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .wallpaper)
        wallpaper.preferences.backgroundBlur = 0.5

        await wallpaper.refresh(displayID: 2)?.value

        #expect(wallpaper.image?.width == otherURL.lastPathComponent.count)
        #expect(screens.loads.map(\.0) == [otherURL])
        #expect(screens.loads.map(\.1) == [0.5])
    }

    @Test func unchangedPictureAndBlurAreNotReloaded() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        screens.urls[1] = mainURL
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .wallpaper)

        await wallpaper.refresh(displayID: 1)?.value
        let second = wallpaper.refresh(displayID: 1)

        #expect(second == nil)
        #expect(screens.loads.count == 1)
        #expect(wallpaper.image != nil)
    }

    @Test func newBlurStrengthReloads() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        screens.urls[1] = mainURL
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .wallpaper)

        await wallpaper.refresh(displayID: 1)?.value
        wallpaper.preferences.backgroundBlur = 0.2
        await wallpaper.refresh()?.value

        #expect(screens.loads.map(\.1) == [1, 0.2])
    }

    // A new desktop picture (or another Space's) under the same display.
    @Test func changedPictureIsReloadedOnTheSameDisplay() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        screens.urls[1] = mainURL
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .wallpaper)

        await wallpaper.refresh(displayID: 1)?.value
        screens.urls[1] = otherURL
        await wallpaper.refresh()?.value

        #expect(screens.loads.map(\.0) == [mainURL, otherURL])
        #expect(wallpaper.image?.width == otherURL.lastPathComponent.count)
    }

    @Test func movingToAnotherScreenLoadsItsPicture() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        screens.urls[1] = mainURL
        screens.urls[2] = otherURL
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .wallpaper)

        await wallpaper.refresh(displayID: 1)?.value
        await wallpaper.refresh(displayID: 2)?.value

        #expect(wallpaper.image?.width == otherURL.lastPathComponent.count)
    }

    @Test func unreadablePictureFallsBackToTheDesktop() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        screens.urls[1] = mainURL
        screens.failing = [mainURL]
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .wallpaper)

        await wallpaper.refresh(displayID: 1)?.value

        #expect(wallpaper.image == nil)
    }

    @Test func screenWithoutAPictureShowsTheDesktop() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .wallpaper)

        let load = wallpaper.refresh(displayID: 1)

        #expect(load == nil)
        #expect(wallpaper.image == nil)
        #expect(screens.loads.isEmpty)
    }

    @Test func switchingBackToTheDesktopDropsThePicture() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        screens.urls[1] = mainURL
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .wallpaper)

        await wallpaper.refresh(displayID: 1)?.value
        wallpaper.preferences.backgroundStyle = .desktop
        wallpaper.refresh()

        #expect(wallpaper.image == nil)
        // Switching back loads it again.
        wallpaper.preferences.backgroundStyle = .wallpaper
        await wallpaper.refresh()?.value
        #expect(wallpaper.image != nil)
        #expect(screens.loads.count == 2)
    }

    // Two refreshes in a row: whichever load finishes last, the newer one is shown.
    @Test func newerRefreshWinsOverALoadInFlight() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screens = FakeScreens()
        screens.urls[1] = mainURL
        screens.urls[2] = otherURL
        let wallpaper = makeWallpaper(screens, defaults: defaults, style: .wallpaper)

        let first = wallpaper.refresh(displayID: 1)
        let second = wallpaper.refresh(displayID: 2)
        await first?.value
        await second?.value

        #expect(wallpaper.image?.width == otherURL.lastPathComponent.count)
    }

    // MARK: - Decoding

    @Test func decodesAndBlursAPictureFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try #require(Self.image(width: 64))
        let data = try #require(NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:]))
        try data.write(to: url)

        let sharp = try #require(DesktopWallpaper.blurredImage(at: url, strength: 0))
        let blurred = try #require(DesktopWallpaper.blurredImage(at: url, strength: 1))

        #expect(sharp.width == 64)
        #expect(blurred.width == 64)
        #expect(blurred.height == sharp.height)
    }

    @Test func notAPictureIsNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper-\(UUID().uuidString).heic")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)

        #expect(DesktopWallpaper.blurredImage(at: url, strength: 1) == nil)
        #expect(DesktopWallpaper.blurredImage(at: url.appendingPathExtension("missing"), strength: 1) == nil)
    }
}
