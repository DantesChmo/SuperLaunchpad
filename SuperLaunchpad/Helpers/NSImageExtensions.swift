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
        pngData(pixelSize: pixelSize, drawingIn: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    }

    // Same square bitmap, with the image scaled to fit and centred, so a
    // picture that isn't square (a photo, a screenshot) keeps its proportions.
    func fittedPNGData(pixelSize: Int) -> Data? {
        guard size.width > 0, size.height > 0 else { return nil }
        let side = CGFloat(pixelSize)
        let scale = min(side / size.width, side / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        let rect = NSRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height)
        return pngData(pixelSize: pixelSize, drawingIn: rect)
    }

    private func pngData(pixelSize: Int, drawingIn rect: NSRect) -> Data? {
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
        draw(in: rect,
             from: .zero,
             operation: .copy,
             fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
