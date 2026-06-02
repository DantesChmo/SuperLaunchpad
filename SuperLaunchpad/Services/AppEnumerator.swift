import AppKit

struct AppEnumerator {
    static let directories = ["/Applications", "/System/Applications"]

    static func enumerate() -> [AppEntry] {
        let fm = FileManager.default
        var results: [AppEntry] = []
        var seen = Set<String>()

        for dir in directories {
            scanDirectory(URL(fileURLWithPath: dir), fileManager: fm, results: &results, seen: &seen)
        }

        return results
    }

    private static func scanDirectory(_ directory: URL, fileManager fm: FileManager, results: inout [AppEntry], seen: inout Set<String>) {
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls {
            if url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }

                seen.insert(bundleID)

                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent

                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let resized = icon.resized(to: NSSize(width: 128, height: 128))
                let iconData = resized.pngData()

                results.append(AppEntry(
                    bundleIdentifier: bundleID,
                    displayName: displayName,
                    appPath: url.path,
                    iconData: iconData
                ))
            } else if url.hasDirectoryPath, url.pathExtension != "bundle" {
                // Recurse into subdirectories (e.g. /Applications/Utilities/)
                // but skip .bundle directories (contain helper apps)
                scanDirectory(url, fileManager: fm, results: &results, seen: &seen)
            }
        }
    }
}
