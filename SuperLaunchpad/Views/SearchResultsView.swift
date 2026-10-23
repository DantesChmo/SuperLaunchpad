import SwiftUI

// Shown in place of the paged grid while the query is non-empty: a single
// page of matching apps and folders on the same grid metrics, with the
// keyboard selection highlighted. A folder opens over the grid. Reads the results itself so a keystroke re-renders
// only this view, not the launcher around it.
struct SearchResultsView: View {
    let viewModel: LaunchpadViewModel
    let metrics: LayoutMetrics
    let onLaunch: (AppEntry) -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if viewModel.searchResults.isEmpty {
                VStack {
                    Spacer()
                    Text("No Results")
                        .foregroundStyle(.white.opacity(contrast == .increased ? LabelContrast.increasedSecondaryOpacity : LabelContrast.secondaryOpacity))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                AppGridPageView(
                    items: viewModel.searchResults,
                    metrics: metrics,
                    selectedID: viewModel.selectedResult?.id,
                    onLaunch: onLaunch,
                    onOpenFolder: { viewModel.openFolderFromSearch($0) }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-results")
    }
}
