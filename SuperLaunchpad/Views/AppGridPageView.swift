import SwiftUI

struct AppGridPageView: View {
    let items: [LaunchpadItem]
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void

    private var columns: [SwiftUI.GridItem] {
        Array(repeating: SwiftUI.GridItem(.fixed(metrics.itemWidth), spacing: 0), count: Grid.columns)
    }

    var body: some View {
        VStack {
            LazyVGrid(columns: columns, alignment: .center, spacing: metrics.rowSpacing) {
                ForEach(items) { item in
                    // GridItem cell: Spacers absorb extra height,
                    // so the inner view only gets its intrinsic size.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        switch item {
                        case .app(let app):
                            AppIconView(app: app, metrics: metrics) {
                                onLaunch(app)
                            }
                        case .folder(let folder, let apps):
                            FolderIconView(folder: folder, apps: apps, metrics: metrics) {
                                onOpenFolder(folder)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: metrics.itemHeight)
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            Spacer(minLength: 0)
        }
    }
}
