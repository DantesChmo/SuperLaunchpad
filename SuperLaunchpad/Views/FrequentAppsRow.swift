import SwiftUI

// Settings → Search: the most launched apps in one row between the search
// field and the grid, on the grid's columns. Click only: the arrow keys and
// Return keep paging the grid. Not part of the layout, so in edit mode it is
// dimmed and ignores clicks rather than jiggling.
struct FrequentAppsRow: View {
    let apps: [AppEntry]
    let metrics: LayoutMetrics
    let isEditing: Bool
    let onLaunch: (AppEntry) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(apps) { app in
                GridCellView(item: .app(app), metrics: metrics, onLaunch: onLaunch, onOpenFolder: { _ in })
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(height: metrics.itemHeight)
        .environment(\.isEditing, false)
        .allowsHitTesting(!isEditing)
        .opacity(isEditing ? FrequentApps.editingOpacity : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frequently Used")
        .accessibilityIdentifier("frequent-apps")
    }
}
