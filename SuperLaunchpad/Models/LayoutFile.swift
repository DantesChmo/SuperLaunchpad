import Foundation

// A layout saved to a file: pages of apps and folders (with titles and
// covers) by bundle ID, the hidden apps, and the user's custom icons (base64
// PNG). The apps' own icons and the folder IDs are left out, so the file can
// be loaded on another Mac. Pure: encoding, decoding and `apply` never touch
// the DB or the file system.
//
// JSON:
//   {
//     "formatVersion": 1,
//     "pages": [[{ "app": "com.apple.Safari" },
//                { "folder": "Utilities", "apps": ["com.apple.Terminal"],
//                  "cover": { "emoji": "🛠️" } }]],
//     "hiddenApps": ["com.example.helper"],
//     "customIcons": { "com.apple.Safari": "iVBORw0KGgo…" }
//   }
//
// Covers and custom icons (1.9.0) are keys older builds skip, so they still
// read the file and the version stays 1. A folder cover is
// `{ "emoji": "…" }` or `{ "image": "<base64 PNG>" }`.
struct LayoutFile: Equatable {
    // Bump when the format changes in a way older builds can't read
    // (2.0.0 adds the grid size).
    static let currentFormatVersion = 1

    enum Item: Equatable {
        case app(String)
        case folder(title: String, apps: [String], cover: FolderCover? = nil)
    }

    var formatVersion = LayoutFile.currentFormatVersion
    var pages: [[Item]]
    var hiddenApps: [String]
    // PNGs by bundle ID. `nil` for a file saved before 1.9.0: loading it
    // keeps the icons set here. Otherwise loading sets exactly these.
    var customIcons: [String: Data]?

    init(pages: [[Item]], hiddenApps: [String] = [], customIcons: [String: Data]? = nil) {
        self.pages = pages
        self.hiddenApps = hiddenApps
        self.customIcons = customIcons
    }

    // The layout as shown on screen (`GridLayout` groups the rows the same way
    // the grid does). Hidden apps by name.
    init(apps: [AppEntry], folders: [FolderEntry]) {
        let layout = GridLayout(apps: apps, folders: folders)
        let covers = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.cover) })
        pages = layout.pages.map { page in
            page.compactMap { item -> Item? in
                switch item {
                case .app(let id):
                    return .app(id)
                case .folder(let id):
                    guard let folder = layout.folders[id] else { return nil }
                    return .folder(title: folder.title, apps: folder.appIDs, cover: covers[id] ?? nil)
                }
            }
        }
        hiddenApps = apps.filter(\.isHidden)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map(\.bundleIdentifier)
        customIcons = Dictionary(uniqueKeysWithValues: apps.compactMap { app in
            app.customIconData.map { (app.bundleIdentifier, $0) }
        })
    }

    // MARK: - Encoding

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    // The version is checked before the rest is read, so a newer file is
    // reported as newer rather than as damaged.
    static func decode(_ data: Data) throws -> LayoutFile {
        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: data)
        } catch {
            throw LayoutFileError.notALayoutFile
        }
        guard header.formatVersion <= currentFormatVersion else {
            throw LayoutFileError.newerFormat(header.formatVersion)
        }
        guard header.formatVersion >= 1 else {
            throw LayoutFileError.notALayoutFile
        }
        do {
            return try JSONDecoder().decode(LayoutFile.self, from: data)
        } catch {
            throw LayoutFileError.notALayoutFile
        }
    }

    private struct Header: Decodable {
        let formatVersion: Int
    }

    // MARK: - Applying

    struct Applied {
        var apps: [AppEntry]
        var folders: [FolderEntry]
        // In the file but not installed here.
        var skippedApps: [String]
        // Installed here but not in the file: put after the last item.
        var appendedApps: [String]
    }

    // Lays out `apps` (every installed app) as the file says. Apps the file
    // doesn't have go after the last item by name; an app hidden here that
    // the file doesn't mention stays hidden. Folders left without apps are
    // dropped; a page longer than `pageCapacity` spills onto new pages.
    // Folders get the file's covers; apps get its custom icons, unless the
    // file has none (`customIcons == nil`) and they keep theirs.
    func apply(
        to apps: [AppEntry],
        pageCapacity: Int = Grid.appsPerPage,
        makeFolderID: () -> String = { UUID().uuidString }
    ) -> Applied {
        let installed = Set(apps.map(\.bundleIdentifier))
        var placed: Set<String> = []
        var skipped: [String] = []

        // An app listed twice keeps its first place.
        func take(_ id: String) -> Bool {
            guard installed.contains(id) else {
                if !skipped.contains(id) {
                    skipped.append(id)
                }
                return false
            }
            return placed.insert(id).inserted
        }

        var folders: [String: GridLayout.Folder] = [:]
        var covers: [String: FolderCover] = [:]
        var pages: [[GridLayout.Item]] = []
        for page in self.pages {
            var items: [GridLayout.Item] = []
            for item in page {
                switch item {
                case .app(let id):
                    if take(id) {
                        items.append(.app(id))
                    }
                case .folder(let title, let members, let cover):
                    let present = members.filter(take)
                    guard !present.isEmpty else { continue }
                    let id = makeFolderID()
                    covers[id] = cover
                    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    folders[id] = GridLayout.Folder(
                        title: trimmed.isEmpty ? EditingModel.defaultFolderTitle : trimmed,
                        appIDs: present
                    )
                    items.append(.folder(id))
                }
            }
            pages.append(contentsOf: items.chunked(by: pageCapacity))
        }

        var hidden: Set<String> = []
        for id in hiddenApps where take(id) {
            hidden.insert(id)
        }

        let unknown = apps.filter { !placed.contains($0.bundleIdentifier) }
        hidden.formUnion(unknown.filter(\.isHidden).map(\.bundleIdentifier))
        let appended = unknown.filter { !$0.isHidden }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map(\.bundleIdentifier)
        for id in appended {
            if pages.isEmpty || pages[pages.count - 1].count >= pageCapacity {
                pages.append([])
            }
            pages[pages.count - 1].append(.app(id))
        }

        let rows = apps.map { app in
            var app = app
            if let customIcons {
                app.customIconData = customIcons[app.bundleIdentifier]
            }
            app.isHidden = hidden.contains(app.bundleIdentifier)
            if app.isHidden {
                app.pageIndex = nil
                app.orderIndex = nil
                app.folderID = nil
                app.folderOrderIndex = nil
            }
            return app
        }
        let layout = GridLayout(pages: pages, folders: folders, pageCapacity: pageCapacity)
        let result = layout.apply(to: rows, folders: [])
        let resultFolders = result.folders.map { folder in
            var folder = folder
            folder.cover = covers[folder.id]
            return folder
        }
        return Applied(apps: result.apps, folders: resultFolders, skippedApps: skipped, appendedApps: appended)
    }
}

enum LayoutFileError: LocalizedError, Equatable {
    case notALayoutFile
    case newerFormat(Int)

    var errorDescription: String? {
        switch self {
        case .notALayoutFile:
            String(localized: "This file is not a SuperLaunchpad layout.")
        case .newerFormat:
            String(localized: "This layout was saved by a newer version of SuperLaunchpad.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notALayoutFile:
            String(localized: "Choose a file saved with Save Layout to File.")
        case .newerFormat:
            String(localized: "Update SuperLaunchpad to load it. Your layout was not changed.")
        }
    }
}

// MARK: - Codable

extension LayoutFile: Codable {
    private enum CodingKeys: String, CodingKey {
        case formatVersion, pages, hiddenApps, customIcons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        pages = try container.decode([[Item]].self, forKey: .pages)
        hiddenApps = try container.decodeIfPresent([String].self, forKey: .hiddenApps) ?? []
        customIcons = try container.decodeIfPresent([String: Data].self, forKey: .customIcons)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(pages, forKey: .pages)
        try container.encode(hiddenApps, forKey: .hiddenApps)
        try container.encodeIfPresent(customIcons, forKey: .customIcons)
    }
}

extension LayoutFile.Item: Codable {
    private enum CodingKeys: String, CodingKey {
        case app, folder, apps, cover
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .app) {
            self = .app(id)
        } else {
            self = .folder(
                title: try container.decode(String.self, forKey: .folder),
                apps: try container.decode([String].self, forKey: .apps),
                cover: try container.decodeIfPresent(FolderCover.self, forKey: .cover)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let id):
            try container.encode(id, forKey: .app)
        case .folder(let title, let apps, let cover):
            try container.encode(title, forKey: .folder)
            try container.encode(apps, forKey: .apps)
            try container.encodeIfPresent(cover, forKey: .cover)
        }
    }
}

extension FolderCover: Codable {
    private enum CodingKeys: String, CodingKey {
        case emoji, image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let emoji = try container.decodeIfPresent(String.self, forKey: .emoji) {
            self = .emoji(emoji)
        } else {
            self = .image(try container.decode(Data.self, forKey: .image))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .emoji(let emoji):
            try container.encode(emoji, forKey: .emoji)
        case .image(let data):
            try container.encode(data, forKey: .image)
        }
    }
}

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
