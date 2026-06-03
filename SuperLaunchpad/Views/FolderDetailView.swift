import SwiftUI

// The expanded folder popup. Shows when the user clicks a folder tile.
// Has its own internal pager (4×3 grid) for folders with more than 12 apps.
struct FolderDetailView: View {
    let folder: FolderEntry
    let apps: [AppEntry]
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void
    let onClose: () -> Void

    @State private var currentPage: Int = 0

    // Splits the flat `apps` array into pages of `FolderGrid.appsPerPage`
    // (12). `stride(from:to:by:)` walks indices in steps; for each step we
    // slice the apps array. Using `min(...)` on the upper bound handles the
    // (possibly partial) last page.
    private var folderPages: [[AppEntry]] {
        guard !apps.isEmpty else { return [] }
        return stride(from: 0, to: apps.count, by: FolderGrid.appsPerPage).map { start in
            Array(apps[start..<min(start + FolderGrid.appsPerPage, apps.count)])
        }
    }

    // Width of the popup card. `+ 60` is the horizontal padding budget
    // (30 left + 30 right). Sized to make 4 columns of `itemWidth` fit cleanly.
    private var containerWidth: CGFloat {
        metrics.itemWidth * CGFloat(FolderGrid.columns) + 60
    }

    // Icons inside the popup are a touch smaller than on the main grid
    // (0.85×) so a 4-column folder doesn't look like an oversized clone of
    // the 7-column main grid.
    private var folderIconSize: CGFloat {
        metrics.iconSize * 0.85
    }

    private var folderItemWidth: CGFloat {
        (containerWidth - 60) / CGFloat(FolderGrid.columns)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(folder.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            if folderPages.isEmpty {
                Text("Empty Folder")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: 120)
            } else {
                // Inner horizontal pager — re-uses the same
                // `SinglePageBehavior` snapping rule as the main grid.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(folderPages.enumerated()), id: \.offset) { index, page in
                            folderPageGrid(page)
                                .frame(width: containerWidth - 60, height: folderGridHeight)
                                .containerRelativeFrame(.horizontal)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(SinglePageBehavior())
                // `scrollPosition` wants a `Binding<Int?>` but our state is
                // non-optional. The custom Binding adapter unwraps for write
                // and re-wraps for read.
                .scrollPosition(id: Binding(
                    get: { currentPage },
                    set: { if let v = $0 { currentPage = v } }
                ))
                .frame(width: containerWidth - 60, height: folderGridHeight)

                if folderPages.count > 1 {
                    PageIndicatorView(
                        totalPages: folderPages.count,
                        currentPage: currentPage
                    )
                    // Swallow the tap on the indicator. Without this, the
                    // tap propagates up to the dimmed background and closes
                    // the folder — unwanted UX.
                    .onTapGesture {
                    }
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .frame(width: containerWidth)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20)
        )
        // Same swallow-the-tap trick: tapping anywhere inside the popup card
        // must NOT close the folder. Only taps on the surrounding dim layer
        // (in LaunchpadView) should close it.
        .onTapGesture {
        }
        .accessibilityIdentifier("folder-detail")
        .accessibilityLabel(folder.title)
    }

    private var folderGridHeight: CGFloat {
        let itemHeight = folderIconSize + 6 + metrics.labelFont * 3
        return itemHeight * CGFloat(FolderGrid.rows) + CGFloat(FolderGrid.rows - 1) * 8
    }

    private func folderPageGrid(_ page: [AppEntry]) -> some View {
        let columns = Array(repeating: GridItem(.fixed(folderItemWidth), spacing: 0), count: FolderGrid.columns)

        return VStack {
            LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
                ForEach(page) { app in
                    FolderAppIconView(
                        app: app,
                        iconSize: folderIconSize,
                        labelFont: metrics.labelFont,
                        labelWidth: folderItemWidth * 0.85
                    ) {
                        onLaunch(app)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// `private` means: only `FolderDetailView` can use this type. We have a
// near-duplicate of `GridItemContainer` here rather than reusing it because
// the popup wants its own (smaller) icon and label sizes — passing those in
// would require parameterising `GridItemContainer` further, and the cost of
// a small dedicated copy is lower than the cost of widening the public type.
private struct FolderAppIconView: View {
    let app: AppEntry
    let iconSize: CGFloat
    let labelFont: CGFloat
    let labelWidth: CGFloat
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        // Same outer/inner VStack pattern as `GridItemContainer` — see the
        // comment there for why two stacks (hover hit-box vs. cell sizing).
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                iconImage
                    .frame(width: iconSize, height: iconSize)

                Text(app.displayName)
                    .font(.system(size: labelFont))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: labelWidth)
            }
            .frame(width: iconSize, height: iconSize + 6 + labelFont * 3)
            .scaleEffect(isHovering ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                onTap()
            }
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        if let data = app.iconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
