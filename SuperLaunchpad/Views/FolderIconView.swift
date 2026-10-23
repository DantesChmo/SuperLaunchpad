import SwiftUI

// A folder tile on the main grid. Looks like macOS Launchpad's folders:
// a rounded translucent square containing a 3×3 mini-preview of the first
// nine apps inside the folder, or the cover the user set (an emoji on the
// same square, or an image in its place).
struct FolderIconView: View {
    let folder: FolderEntry
    let apps: [AppEntry]
    let metrics: LayoutMetrics
    // Keyboard selection in search results.
    var isSelected = false
    // The arrow keys' focus is on it (see `KeyboardFocusModel`).
    var isFocused = false
    let onTap: () -> Void

    // 3×3 preview — Apple's convention. Even if the folder has more apps,
    // only the first nine appear on the closed tile.
    private let previewColumns = 3
    private let previewRows = 3

    var body: some View {
        GridItemContainer(metrics: metrics, onTap: onTap) {
            folderIcon
                .frame(width: metrics.iconSize, height: metrics.iconSize)
        } label: {
            // The dot tells a new app went into this folder.
            Text.launcherLabel(folder.title, isNew: apps.contains(where: \.isNew), fontSize: metrics.labelFont)
                .foregroundStyle(.white)
                .launcherLabelShadow()
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: metrics.labelWidth)
        }
        .background {
            RoundedRectangle(cornerRadius: Search.selectionCornerRadius)
                .fill(.white.opacity(isSelected ? Search.selectionOpacity : 0))
                .padding(-metrics.iconSize * Search.selectionOutsetRatio)
        }
        .keyboardFocusRing(isFocused, iconSize: metrics.iconSize)
        .launcherItemAccessibility(
            label: folder.title,
            hint: apps.count == 1
                ? String(localized: "Folder with 1 app. Opens the folder")
                : String(localized: "Folder with \(apps.count) apps. Opens the folder"),
            onActivate: onTap
        )
        .folderContextMenu(folder)
        .newAppAccessibilityValue(apps.contains(where: \.isNew))
        .accessibilityIdentifier("folder-icon")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var folderIcon: some View {
        if let image = IconCache.shared.coverImage(for: folder) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: metrics.iconSize * 0.2))
        } else if let emoji = folder.coverEmoji {
            RoundedRectangle(cornerRadius: metrics.iconSize * 0.2)
                .fill(.white.opacity(0.15))
                .overlay(
                    Text(emoji)
                        .font(.system(size: metrics.iconSize * CustomIcons.emojiCoverScale))
                )
        } else {
            previewGrid
        }
    }

    private var previewGrid: some View {
        // Sizes are derived from `iconSize` so the preview scales with display
        // resolution. `0.22` and `0.06` are tuned to visually match Launchpad.
        let miniSize = metrics.iconSize * 0.22
        let spacing = metrics.iconSize * 0.06
        // `prefix(9)` returns up to 9 elements (less if the folder has fewer).
        let previewApps = Array(apps.prefix(previewColumns * previewRows))

        return RoundedRectangle(cornerRadius: metrics.iconSize * 0.2)
            .fill(.white.opacity(0.15))
            // `.overlay` paints the inner 3×3 grid on top of the rounded
            // background while keeping the background's hit area for hover.
            .overlay(
                VStack(spacing: spacing) {
                    // Nested ForEach for the 3×3 grid. `0..<n` ranges are
                    // `Range<Int>` — they need `id: \.self` because they
                    // don't conform to `Identifiable`.
                    ForEach(0..<previewRows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<previewColumns, id: \.self) { col in
                                let index = row * previewColumns + col
                                // Three cases: real icon, placeholder for an
                                // app without iconData, or empty filler so
                                // shorter folders still produce a square grid.
                                if index < previewApps.count,
                                   let nsImage = IconCache.shared.image(for: previewApps[index]) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: miniSize, height: miniSize)
                                        // Rounded clipping mask gives macOS's
                                        // squircle look at small sizes.
                                        .clipShape(RoundedRectangle(cornerRadius: miniSize * 0.2))
                                } else if index < previewApps.count {
                                    RoundedRectangle(cornerRadius: miniSize * 0.2)
                                        .fill(.white.opacity(0.2))
                                        .frame(width: miniSize, height: miniSize)
                                } else {
                                    // `Color.clear` with a frame keeps the
                                    // grid alignment when there are <9 apps.
                                    Color.clear
                                        .frame(width: miniSize, height: miniSize)
                                }
                            }
                        }
                    }
                }
                .padding(metrics.iconSize * 0.1)
            )
    }
}
