import Foundation

// Readable names for an app's `LSApplicationCategoryType`, used to title the
// folder made by dropping one app on another (named after the target app).
enum AppCategory {
    static let typeKey = "LSApplicationCategoryType"
    private static let prefix = "public.app-category."

    // Apple's categories whose name is not just the identifier capitalized.
    private static let names: [String: String] = [
        "developer-tools": "Developer Tools",
        "graphics-design": "Graphics & Design",
        "healthcare-fitness": "Health & Fitness",
        "social-networking": "Social Networking",
    ]

    // The folder title for an app at `path`, or `fallback` when the bundle
    // declares no category.
    static func folderTitle(forAppAt path: String, fallback: String) -> String {
        let type = Bundle(path: path)?.object(forInfoDictionaryKey: typeKey) as? String
        return title(forCategoryType: type) ?? fallback
    }

    // "public.app-category.developer-tools" → "Developer Tools". Every
    // "…-games" subcategory is "Games". Nil for a missing or malformed type.
    static func title(forCategoryType type: String?) -> String? {
        guard let type, type.hasPrefix(prefix) else { return nil }
        let name = String(type.dropFirst(prefix.count)).lowercased()
        guard !name.isEmpty else { return nil }
        if let known = names[name] {
            return known
        }
        if name.hasSuffix("-games") {
            return "Games"
        }
        return name
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
