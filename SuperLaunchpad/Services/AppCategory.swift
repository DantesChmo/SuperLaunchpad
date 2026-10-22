import Foundation

// Coarse grouping used to build the first-run layout when there is no system
// Launchpad DB to import (macOS 26 Tahoe dropped it). Several App Store
// categories collapse into one case so folders stay few and meaningful.
enum AppCategory: CaseIterable {
    case utilities
    case productivity
    case developerTools
    case games
    case social
    case entertainment
    case creativity
    case reference
    case lifestyle
    case uncategorized

    var folderTitle: String {
        switch self {
        case .utilities: String(localized: "Utilities")
        case .productivity: String(localized: "Productivity")
        case .developerTools: String(localized: "Developer Tools")
        case .games: String(localized: "Games")
        case .social: String(localized: "Social")
        case .entertainment: String(localized: "Entertainment")
        case .creativity: String(localized: "Creativity")
        case .reference: String(localized: "Reference & Education")
        case .lifestyle: String(localized: "Lifestyle")
        case .uncategorized: String(localized: "Other")
        }
    }

    // Reads `LSApplicationCategoryType` from the app's Info.plist. Some Apple
    // apps ship without the key, hence the override table.
    static func of(_ app: AppEntry) -> AppCategory {
        if let override = overrides[app.bundleIdentifier] {
            return override
        }
        let bundle = Bundle(url: URL(fileURLWithPath: app.appPath))
        let type = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        return type.map(from(categoryType:)) ?? .uncategorized
    }

    static func from(categoryType: String) -> AppCategory {
        let prefix = "public.app-category."
        guard categoryType.hasPrefix(prefix) else { return .uncategorized }
        let name = String(categoryType.dropFirst(prefix.count))
        if name == "games" || name.hasSuffix("-games") {
            return .games
        }
        return categoryTypes[name] ?? .uncategorized
    }

    private static let categoryTypes: [String: AppCategory] = [
        "utilities": .utilities,
        "productivity": .productivity,
        "business": .productivity,
        "developer-tools": .developerTools,
        "social-networking": .social,
        "entertainment": .entertainment,
        "music": .entertainment,
        "sports": .entertainment,
        "photography": .creativity,
        "video": .creativity,
        "graphics-design": .creativity,
        "reference": .reference,
        "education": .reference,
        "news": .reference,
        "lifestyle": .lifestyle,
        "healthcare-fitness": .lifestyle,
        "medical": .lifestyle,
        "travel": .lifestyle,
        "weather": .lifestyle,
        "finance": .lifestyle,
    ]

    private static let overrides: [String: AppCategory] = [
        "com.apple.calculator": .utilities,
        "com.apple.clock": .utilities,
        "com.apple.findmy": .utilities,
        "com.apple.Home": .lifestyle,
        "com.apple.Passwords": .utilities,
        "com.apple.mobilephone": .social,
        "com.apple.podcasts": .entertainment,
        "com.apple.stocks": .lifestyle,
        "com.apple.weather": .lifestyle,
        "com.apple.ScreenContinuity": .utilities,
        "com.apple.DiskUtility": .utilities,
        "com.apple.Magnifier": .utilities,
    ]
}
