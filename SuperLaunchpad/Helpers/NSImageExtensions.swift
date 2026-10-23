import AppKit

extension NSImage {
    // Draws the image into a square bitmap of exactly `pixelSize` × `pixelSize`
    // pixels and encodes it as PNG — what we store in the SQLite blob column
    // on `AppEntry.iconData`.
    //
    // An explicit `NSBitmapImageRep` pins the pixel count. `lockFocus` on an
    // `NSImage` would render at the main screen's backing scale instead, so
    // the stored size depended on which display was main during the scan
    // (half of it on a non-Retina one), and its 16-bit samples doubled the
    // PNG size for nothing.
    //
    // `.high` interpolation because app icons are downscaled from larger
    // bitmaps (often 1024×1024); the default produces visibly aliased edges.
    func pngData(pixelSize: Int) -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
             from: .zero,
             operation: .copy,
             fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
