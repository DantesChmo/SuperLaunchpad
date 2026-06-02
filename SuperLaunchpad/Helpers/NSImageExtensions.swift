import AppKit

extension NSImage {
    // `NSImage` is a vector-ish container of representations (multiple sizes /
    // formats). To get raw bytes we go via TIFF (a lossless format AppKit can
    // always produce) and then ask `NSBitmapImageRep` to re-encode as PNG.
    // PNG is what we store in the SQLite blob column on `AppEntry.iconData`.
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // AppKit's old-school drawing API: `lockFocus` makes `self` the current
    // drawing destination, any subsequent draw calls go into it, and
    // `unlockFocus` commits. This must always come in pairs — leaking focus
    // corrupts later drawing.
    //
    // We use `.high` interpolation because app icons are downscaled from larger
    // bitmaps (often 512×512) to 128×128; the default produces visibly aliased
    // edges.
    func resized(to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: size),
             from: NSRect(origin: .zero, size: self.size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
