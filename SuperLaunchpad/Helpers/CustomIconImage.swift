import AppKit
import UniformTypeIdentifiers

// Turns a file the user picked or dropped into a custom icon or folder cover:
// a PNG of `AppIcon.pixelSize` px, like the scanned icons. An image is
// scaled to fit; an app lends its own icon.
enum CustomIconImage {
    static let allowedTypes: [UTType] = [.png, .jpeg, .heic, .icns, .applicationBundle]

    static func isAllowed(_ url: URL) -> Bool {
        guard let type = contentType(of: url) else { return false }
        return allowedTypes.contains { type.conforms(to: $0) }
    }

    // `nil` for a file of another type, or one that doesn't decode.
    // Reads and draws the file: call it off the main thread.
    static func pngData(contentsOf url: URL) -> Data? {
        guard let type = contentType(of: url), allowedTypes.contains(where: { type.conforms(to: $0) }) else {
            return nil
        }
        if type.conforms(to: .applicationBundle) {
            return NSWorkspace.shared.icon(forFile: url.path).pngData(pixelSize: AppIcon.pixelSize)
        }
        return NSImage(contentsOf: url)?.fittedPNGData(pixelSize: AppIcon.pixelSize)
    }

    private static func contentType(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
    }

    // Asks for a file, `nil` when cancelled; what the view model calls,
    // tests swap in their own.
    struct Picker {
        var choose: @MainActor () async -> URL?

        static var live: Picker {
            Picker(choose: { await CustomIconImage.chooseFile() })
        }
    }

    // In-process (the app isn't sandboxed), so the panel can sit above the
    // launcher's `.screenSaver` level.
    @MainActor static func chooseFile() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = String(localized: "Choose an image, or an app to use its icon.")
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.url : nil
    }
}
