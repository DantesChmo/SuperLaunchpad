import SwiftUI

// The launcher's search field. It takes focus every time the launcher is
// shown, so typing starts a query at once; a real `TextField` (rather than
// collecting keyDown characters) keeps IME, dead keys and paste working.
//
// Arrow keys, Return and Escape never reach the field while the launcher is
// open: `LaunchpadPanel` intercepts them for selection, paging and dismissal.
struct SearchBarView: View {
    @Bindable var search: SearchModel
    @FocusState private var isFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var secondaryOpacity: Double {
        contrast == .increased ? LabelContrast.increasedSecondaryOpacity : LabelContrast.secondaryOpacity
    }

    private var placeholderOpacity: Double {
        contrast == .increased ? LabelContrast.increasedSecondaryOpacity : LabelContrast.placeholderOpacity
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(secondaryOpacity))
                .font(.system(size: Search.fieldFontSize))
                .accessibilityHidden(true)
            TextField(
                "Search",
                text: $search.searchText,
                prompt: Text("Search").foregroundStyle(.white.opacity(placeholderOpacity))
            )
            .textFieldStyle(.plain)
            .font(.system(size: Search.fieldFontSize))
            .foregroundStyle(.white)
            .focused($isFocused)
            .accessibilityLabel("Search apps")
            .accessibilityHint("Type to filter apps; arrow keys choose a result, Return opens it")
            .accessibilityIdentifier("search-field")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // `.background(_:in:)` is the modern API that lets you set both a
        // fill style AND a shape in one modifier.
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: Search.fieldCornerRadius))
        .frame(width: Search.fieldWidth)
        .onAppear { isFocused = true }
        .onChange(of: search.searchFocusRequest) { isFocused = true }
    }
}
