import SwiftUI

// Shown in place of the paged grid while the query is non-empty: a single
// page of matching apps on the same grid metrics, with the keyboard
// selection highlighted. Reads the results itself so a keystroke re-renders
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
                    items: viewModel.searchResults.map { .app($0) },
                    metrics: metrics,
                    selectedID: viewModel.selectedResult?.id,
                    onLaunch: onLaunch,
                    onOpenFolder: { _ in }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-results")
    }
}
