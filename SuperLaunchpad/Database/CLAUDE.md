# Database — agent notes

Single GRDB-backed SQLite at `~/Library/Application Support/com.dantes.SuperLaunchpad/apps.db`. One file: `AppDatabase.swift`. Models live in `../Models/`.

## Migrations — append-only

Versions are `"v1"`, `"v2"`, `"v3"`, … Add a new `"vN+1"` block to `migrate()` in `AppDatabase.swift`. **Never edit a shipped migration**, never `DROP TABLE`. Use `.add(column:)` / `.create(table:)` only.

Current schema (after v9):

- `appEntry` — PK `bundleIdentifier`. Cols: `displayName`, `appPath`, `iconData`, `pageIndex?`, `orderIndex?`, `folderID?` (FK → `folderEntry.id`, `.setNull` on delete), `folderOrderIndex?`, `isHidden` (v5, not null, default false; a hidden app has all four position columns nil), `isNew` (v6, not null, default false), `launchCount` (v8, integer, not null, default 0; launches from the launcher, search ranks by it). `iconData` is a PNG of `AppIcon.pixelSize` px; v7 set it to NULL in every row (no schema change) so the launch rescan renders it again at 256 px, positions and flags untouched.
- `folderEntry` — PK `id` (UUID string, generated in code), `title`, `pageIndex`, `orderIndex`, `coverEmoji?`, `coverImageData?` (v9; the folder's cover, at most one set, read as `FolderEntry.cover`; written by `saveLayout` with the row, or alone by `setFolderCover(id:cover:)`).
- `customIcon` (v9) — PK `bundleIdentifier`, `imageData` (not null, PNG of `AppIcon.pixelSize` px). The user's own app icon. No FK to `appEntry`: `deleteStale` / `deleteApp` leave it, so a reinstalled app gets it back. `fetchAllApps` attaches it as `AppEntry.customIconData` (not a column of `appEntry`; `AppEntry.CodingKeys` keeps it out of `save`). Written by `setCustomIcon(_:bundleIdentifier:)` and, for a loaded layout file, `saveCustomIcons(of:)`.
- `appSetting` — PK `key` (`AppSetting.Key` raw value), `value`. Read/write via `setting(_:)` / `setSetting(_:_:)`.

`AppSetting.Key.folderImportDone`: set once the system Launchpad folders were imported (rescan with a system layout), by any `saveLayout`, or backfilled by v4 when apps already sit in folders. While it is set, `mergeNewApps` never re-imports system folders — otherwise dissolving the last folder would bring them back on the next rescan.

`AppSetting.Key.newAppTracking`: set once every app on disk has a row (backfilled by v6 for an existing layout). Only then does a rescan mark apps without a row `isNew`. `recordLaunch(bundleIdentifier:)` clears the flag and adds one to `launchCount`, in one update, on every launch from the launcher. A rescan copies existing rows, so the count survives it.

Migration tests that fill an older schema must insert only that schema's columns (raw `INSERT`): `AppEntry.insert` and `FolderEntry.insert` write every current column.

`AppDatabase.migrator` is exposed so tests can `migrate(_:upTo:)` an older version and check what a later migration does to existing rows.

## Layout edits

Edits (reorder, folders, rename) are computed by the pure `Models/GridLayout.swift` and persisted by the view model:

- `saveLayout(apps:folders:)` — one transaction: upserts every folder and app passed in, deletes folders not in `folders`, sets `folderImportDone`.
- `renameFolder(id:title:)` — title only.

**Invariant:** an app is either on a page (`pageIndex` + `orderIndex` set, `folderID == nil`) **or** in a folder (`folderID` + `folderOrderIndex` set, `pageIndex == nil` && `orderIndex == nil`). Setting both is a bug. Enforce in code, not via SQL constraints.

## Records

```swift
extension AppEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "appEntry"
    enum Columns: String, ColumnExpression {
        case bundleIdentifier, displayName, pageIndex, orderIndex, folderID, folderOrderIndex
    }
}
```

- `struct` + `Codable, Identifiable, Equatable`.
- `enum Columns: String, ColumnExpression` is **mandatory** — never reference column names as raw strings.
- Persistence conformances go in a separate `extension`, never on the model itself.

## Queries

- Chain off the type: `AppEntry.filter(...).order(...).fetchAll(db)`.
- Use `Columns.x.ascNullsLast` / `Columns.x.descNullsLast` for nullable order keys.
- Use `Columns.displayName.collating(.localizedCaseInsensitiveCompare)` for human-visible sort — never raw `<`.

## Writes

- `dbQueue.write { db in ... }` — wraps in a transaction.
- Batch writes: loop inside one `write` block, not one `write` per row.
- Upsert by PK: `entry.save(db)`. No manual `INSERT OR REPLACE`.

## Threading

- `AppDatabase` itself is `DatabaseQueue`-backed → thread-safe for reads/writes.
- Callers (mostly `LaunchpadViewModel`) marshal results to `@MainActor`. Don't block the main thread on big reads — `Task.detached` first.

## Errors

- Prefer `try?` + explicit default at call sites: `let apps = (try? db.fetchAllApps()) ?? []`.
- `do/catch` only when the error path drives distinct behavior (rare here).

## When adding a new field

1. Append `"vN+1"` migration with `t.add(column:)`.
2. Add the property to the model `struct` (optional if column is nullable, default value if not).
3. Extend `enum Columns`.
4. Add a fixture variant in tests if relevant.
5. **Do not** edit `"v3"` (or any prior version) to "include" the new column.

## Test DB

Use `makeTempDB()` from `SuperLaunchpadTests/AppDatabaseTests.swift` — fresh on-disk SQLite per test, runs migrations. Never share a DB between tests.

## Don't

- ❌ `DROP TABLE` / `.rename(table:)` / destructive migrations.
- ❌ Raw SQL strings unless GRDB's query interface genuinely can't express it (it almost always can).
- ❌ Reading the system Launchpad DB from here — that's `Services/SystemLaunchpadDB.swift`, read-only.
- ❌ Adding a second persistence layer (UserDefaults for ordering, JSON files, etc.). One `AppDatabase`, extend it.
