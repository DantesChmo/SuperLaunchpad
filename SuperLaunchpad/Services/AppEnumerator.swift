import AppKit

// Scans the on-disk application directories and produces `AppEntry` values
// for every installed `.app` bundle. Pure file-system work — no DB, no UI.
//
// Called from a background task (`Task.detached` in `LaunchpadViewModel.loadApps`)
// because the icon extraction loop is slow (~hundreds of ms on a full Mac).
struct AppEnumerator {
    static let directories = ["/Applications", "/System/Applications"]

    static func enumerate() -> [AppEntry] {
        let fm = FileManager.default
        var results: [AppEntry] = []
        // De-dupe by bundleID — the same app can technically appear in both
        // /Applications and /System/Applications (rare, but possible after
        // OS upgrades that leave stale copies).
        var seen = Set<String>()

        for dir in directories {
            scanDirectory(URL(fileURLWithPath: dir), fileManager: fm, results: &results, seen: &seen)
        }

        return results
    }

    // `NSWorkspace.icon(forFile:)` returns the best-resolution icon macOS
    // knows about (often 1024×1024 from the .icns inside the bundle). We
    // downsize it to `AppIcon.pixelSize` PNG once and persist that — decoding
    // the full resolution for every grid cell would be wasteful.
    static func iconData(forAppAt path: String) -> Data? {
        NSWorkspace.shared.icon(forFile: path).pngData(pixelSize: AppIcon.pixelSize)
    }

    // `inout` lets us mutate the caller's `results`/`seen` instead of returning
    // and merging on every recursive call. Cheap and idiomatic for recursive
    // accumulation patterns in Swift.
    private static func scanDirectory(_ directory: URL, fileManager fm: FileManager, results: inout [AppEntry], seen: inout Set<String>) {
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls {
            if url.pathExtension == "app" {
                // `Bundle(url:)` reads Info.plist + resource maps. If it fails,
                // the .app is malformed — skip silently.
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }

                seen.insert(bundleID)

                // Display name fallback chain — same one the Finder uses:
                //   1. CFBundleDisplayName (localised marketing name)
                //   2. CFBundleName        (short Info.plist name)
                //   3. Filename without ".app" (last resort)
                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent

                results.append(AppEntry(
                    bundleIdentifier: bundleID,
                    displayName: displayName,
                    appPath: url.path,
                    iconData: iconData(forAppAt: url.path)
                ))
            } else if url.hasDirectoryPath, url.pathExtension != "bundle" {
                // Recurse into plain subdirectories like /Applications/Utilities/.
                // `.bundle` directories are skipped because they typically contain
                // helper apps the user shouldn't see in the launcher (XPC services,
                // login items, etc.).
                scanDirectory(url, fileManager: fm, results: &results, seen: &seen)
            }
        }
    }
}
