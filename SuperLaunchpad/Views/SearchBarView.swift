import SwiftUI

// Visual placeholder for a future search field. Filtering is intentionally
// not wired (see AGENTS.md > "Known limitations"): adding it requires a
// `TextField`, debounce, scope decisions, and ViewModel filtering — out of
// scope for the current release.
//
// Kept as a `Text("Search")` "fake" so the layout reserves space and the UI
// matches the design.
struct SearchBarView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
                .font(.system(size: 14))
            Text("Search")
                .foregroundStyle(.white.opacity(0.4))
                .font(.system(size: 14))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // `.background(_:in:)` is the modern API that lets you set both a
        // fill style AND a shape in one modifier.
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .frame(width: 200)
    }
}
