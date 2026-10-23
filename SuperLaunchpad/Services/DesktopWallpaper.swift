import AppKit
import CoreImage
import ImageIO

// Settings → Appearance → Blurred wallpaper: the desktop picture of the
// screen the launcher is on, decoded small and blurred once, off the main
// thread. Drawn instead of the live `NSVisualEffectView`, which keeps sampling
// the screen every frame. `LaunchpadPanel` refreshes it whenever it places
// itself on a screen (every show, display changes) and when the Space changes,
// since each Space can have its own picture.
@MainActor
@Observable
final class DesktopWallpaper {
    // Where pictures come from; tests swap in their own.
    struct Provider {
        // The desktop picture's file for a display, by `CGDirectDisplayID`.
        var imageURL: @MainActor (UInt32) -> URL?
        // Decodes and blurs (strength 0…1); nil when the file isn't an image
        // (some dynamic wallpapers). Runs off the main thread.
        var loadImage: @Sendable (URL, Double) -> CGImage?

        static var live: Provider {
            Provider(
                imageURL: { displayID in
                    guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
                    return NSWorkspace.shared.desktopImageURL(for: screen)
                },
                loadImage: { url, blur in
                    DesktopWallpaper.blurredImage(at: url, strength: blur)
                }
            )
        }
    }

    // What the launcher draws behind the grid.
    enum Source: Equatable {
        case desktop
        case wallpaper(URL)
    }

    // Pure: the wallpaper only when it is chosen and the screen has one.
    static func source(style: BackgroundStyle, wallpaperURL: URL?) -> Source {
        guard style == .wallpaper, let wallpaperURL else { return .desktop }
        return .wallpaper(wallpaperURL)
    }

    // The blurred picture; nil means the launcher shows the blurred desktop.
    private(set) var image: CGImage?

    @ObservationIgnored var preferences = Preferences()
    @ObservationIgnored private let provider: Provider
    @ObservationIgnored private var displayID: UInt32?
    // What `image` (or the load in flight) was made from.
    @ObservationIgnored private var loaded: Loaded?

    private struct Loaded: Equatable {
        let url: URL
        let blur: Double
    }

    init(provider: Provider) {
        self.provider = provider
    }

    // Re-reads the setting and the screen's picture. `displayID` is the
    // screen the launcher now covers; nil keeps the previous one. Returns the
    // load, if one started, so tests can await it.
    @discardableResult
    func refresh(displayID: UInt32? = nil) -> Task<Void, Never>? {
        if let displayID {
            self.displayID = displayID
        }
        let url = self.displayID.flatMap { provider.imageURL($0) }
        guard case .wallpaper(let url) = Self.source(style: preferences.backgroundStyle, wallpaperURL: url) else {
            // Nothing to keep in memory while the desktop is shown.
            loaded = nil
            image = nil
            return nil
        }
        let wanted = Loaded(url: url, blur: preferences.backgroundBlur)
        guard wanted != loaded else { return nil }
        loaded = wanted
        let loadImage = provider.loadImage
        return Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                loadImage(wanted.url, wanted.blur)
            }.value
            // A newer refresh (another screen, Space or setting) wins.
            guard let self, self.loaded == wanted else { return }
            self.image = image
        }
    }

    // MARK: - Decoding

    nonisolated static func blurredImage(at url: URL, strength: Double) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: BackgroundAppearance.wallpaperMaxPixelSize,
        ]
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return nil }
        guard strength > 0 else { return decoded }
        let input = CIImage(cgImage: decoded)
        let radius = Double(decoded.width) * BackgroundAppearance.wallpaperBlurRatio * strength
        // Clamped first so the edges don't fade to transparent, then cropped
        // back to the picture.
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: input.extent)
        return CIContext().createCGImage(blurred, from: input.extent)
    }
}

extension NSScreen {
    // Stable while the display is connected, unlike the index in `screens`.
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
