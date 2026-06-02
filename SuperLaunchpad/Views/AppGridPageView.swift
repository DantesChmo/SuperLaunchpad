import SwiftUI

// One page of the grid: a fixed N×M layout of apps and/or folders.
struct AppGridPageView: View {
    let items: [LaunchpadItem]
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void

    // Note the `SwiftUI.` prefix — we have our own `LaunchpadItem` (the enum
    // in Models/) plus the project file is named `GridItem.swift`, both of
    // which shadow SwiftUI's `GridItem`. Fully qualifying disambiguates.
    private var columns: [SwiftUI.GridItem] {
        // `.fixed(width)` makes each column exactly `itemWidth` wide so the
        // grid lines up across pages (vs. `.flexible` which would re-balance
        // based on available space and produce subtle jitter on resize).
        Array(repeating: SwiftUI.GridItem(.fixed(metrics.itemWidth), spacing: 0), count: Grid.columns)
    }

    var body: some View {
        VStack {
            // `LazyVGrid` only materialises rows that are scrolled into view.
            // For our 5-row grid it's not a perf win (everything is visible),
            // but it's also the easiest API for fixed-column layouts.
            LazyVGrid(columns: columns, alignment: .center, spacing: metrics.rowSpacing) {
                ForEach(items) { item in
                    // Cell layout trick: wrap each icon in a VStack with
                    // top/bottom Spacers. The Spacers absorb leftover vertical
                    // space, so the icon centers vertically within `itemHeight`
                    // regardless of label line count (1 vs. 2 lines).
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // `switch` over the LaunchpadItem sum type — each case
                        // gets compile-time exhaustiveness checking.
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
            // Pushes the grid to the top of the page so partial rows hug the
            // top edge instead of floating in the middle of the page.
            Spacer(minLength: 0)
        }
    }
}
