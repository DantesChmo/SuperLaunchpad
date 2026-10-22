import AppKit
import ImageIO

// Decoded app icons keyed by bundle identifier, so view bodies never decode
// PNG bytes themselves. Without it every re-render (including each frame of a
// page swipe) ran `NSImage(data:)` on the main thread.
//
// An entry remembers a cheap fingerprint of the bytes it was decoded from;
// when an app's `iconData` changes (app update, rescan) the fingerprint no
// longer matches and the icon is decoded again.
@MainActor
final class IconCache {
    static let shared = IconCache()

    // Byte count plus a hash of a small slice from the middle of the PNG.
    // Hashing the whole blob on every lookup would cost more than the cache
    // saves; the header and trailer are near-constant across PNGs, so the
    // sample is taken from the middle where the pixel data differs.
    struct Fingerprint: Equatable {
        let count: Int
        let sampleHash: Int
    }

    private struct Entry {
        let fingerprint: Fingerprint
        let image: NSImage
    }

    nonisolated private static let fingerprintSampleLength = 64

    private var entries: [String: Entry] = [:]

    func image(for app: AppEntry) -> NSImage? {
        image(bundleIdentifier: app.bundleIdentifier, data: app.iconData)
    }

    func image(bundleIdentifier: String, data: Data?) -> NSImage? {
        guard let data else {
            entries[bundleIdentifier] = nil
            return nil
        }
        let fingerprint = Self.fingerprint(of: data)
        if let entry = entries[bundleIdentifier], entry.fingerprint == fingerprint {
            return entry.image
        }
        guard let cgImage = Self.decode(data) else {
            entries[bundleIdentifier] = nil
            return nil
        }
        let image = Self.makeImage(cgImage)
        entries[bundleIdentifier] = Entry(fingerprint: fingerprint, image: image)
        return image
    }

    // Decodes the icons that aren't cached yet off the main thread. Intended to
    // run right after the app list is (re)loaded, so the first swipe to a page
    // finds its icons ready.
    func prewarm(_ apps: [AppEntry]) async {
        let pending: [(String, Data)] = apps.compactMap { app in
            guard let data = app.iconData, !containsCurrentIcon(for: app) else { return nil }
            return (app.bundleIdentifier, data)
        }
        guard !pending.isEmpty else { return }

        let decoded = await Task.detached(priority: .utility) {
            pending.compactMap { bundleIdentifier, data -> (String, Fingerprint, CGImage)? in
                guard let cgImage = IconCache.decode(data) else { return nil }
                return (bundleIdentifier, IconCache.fingerprint(of: data), cgImage)
            }
        }.value

        for (bundleIdentifier, fingerprint, cgImage) in decoded {
            // A lookup during the decode may already have stored this icon.
            // An entry with a different fingerprint is stale and gets replaced.
            guard entries[bundleIdentifier]?.fingerprint != fingerprint else { continue }
            entries[bundleIdentifier] = Entry(fingerprint: fingerprint, image: Self.makeImage(cgImage))
        }
    }

    // True when the app's current `iconData` is already decoded, i.e. a
    // lookup would not decode anything.
    func containsCurrentIcon(for app: AppEntry) -> Bool {
        guard let data = app.iconData, let entry = entries[app.bundleIdentifier] else { return false }
        return entry.fingerprint == Self.fingerprint(of: data)
    }

    func removeAll() {
        entries.removeAll()
    }

    // MARK: - Decoding

    nonisolated static func fingerprint(of data: Data) -> Fingerprint {
        let length = min(fingerprintSampleLength, data.count)
        let start = data.startIndex + (data.count - length) / 2
        var hasher = Hasher()
        hasher.combine(data[start..<(start + length)])
        return Fingerprint(count: data.count, sampleHash: hasher.finalize())
    }

    // `NSImage(data:)` defers the actual PNG decode until first draw, which
    // would land on the main thread mid-animation anyway. `CGImageSource` with
    // `shouldCacheImmediately` decodes into a bitmap right here.
    nonisolated private static func decode(_ data: Data) -> CGImage? {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    // `.zero` size makes `NSImage` use the bitmap's pixel dimensions, matching
    // what `NSImage(data:)` produced for the stored PNGs.
    private static func makeImage(_ cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: .zero)
    }
}
