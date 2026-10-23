import AppKit

// macOS 26 draws app icons in the style chosen in System Settings →
// Appearance → Icon & widget style (default, dark, clear, tinted), and
// `NSWorkspace.icon(forFile:)` already returns that variant. Stored icons are
// PNGs made at scan time, though, so a style change shows only after the next
// rescan. There is no public notification for the change: this renders one
// reference icon and tells when it comes out different, and the app then
// rescans (which rewrites every `iconData`).
@MainActor
final class IconStyleProbe {
    private let render: @MainActor () -> Data?
    private var last: Data?

    init(render: @escaping @MainActor () -> Data? = IconStyleProbe.renderReferenceIcon) {
        self.render = render
    }

    // True when the reference icon renders differently than at the previous
    // check; the first check only records it. A failed render changes nothing.
    func styleDidChange() -> Bool {
        guard let current = render() else { return false }
        defer { last = current }
        guard let last else { return false }
        return current != last
    }

    static func renderReferenceIcon() -> Data? {
        NSWorkspace.shared.icon(forFile: IconStyle.referenceAppPath).pngData(pixelSize: IconStyle.probePixelSize)
    }
}
