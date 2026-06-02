import SwiftUI

struct FolderDetailView: View {
    let folder: FolderEntry
    let apps: [AppEntry]
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void
    let onClose: () -> Void

    @State private var currentPage: Int = 0

    private var folderPages: [[AppEntry]] {
        guard !apps.isEmpty else { return [] }
        return stride(from: 0, to: apps.count, by: FolderGrid.appsPerPage).map { start in
            Array(apps[start..<min(start + FolderGrid.appsPerPage, apps.count)])
        }
    }

    private var containerWidth: CGFloat {
        metrics.itemWidth * CGFloat(FolderGrid.columns) + 60
    }

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
                // Horizontal pager
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
                    .onTapGesture {
                        // Prevent tap from propagating
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
        .onTapGesture {
            // Consume tap to prevent it from closing the folder
        }
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

private struct FolderAppIconView: View {
    let app: AppEntry
    let iconSize: CGFloat
    let labelFont: CGFloat
    let labelWidth: CGFloat
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        // Outer: takes whatever size parent gives
        VStack(spacing: 0) {
            // Inner: explicit size, hover lives here
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
