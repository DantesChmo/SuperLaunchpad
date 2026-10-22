import SwiftUI

// A single app cell: icon on top, name below. Shared hover/tap behaviour
// lives in `GridItemContainer`.
struct AppIconView: View {
    let app: AppEntry
    let metrics: LayoutMetrics
    var isSelected = false
    let onTap: () -> Void

    var body: some View {
        // `GridItemContainer` is a generic view that takes two `@ViewBuilder`
        // closures — `icon:` and `label:`. The trailing closure syntax with
        // a labelled second closure (`} label: {`) is Swift's "multiple
        // trailing closures" feature.
        GridItemContainer(metrics: metrics, onTap: onTap) {
            iconImage
                .frame(width: metrics.iconSize, height: metrics.iconSize)
        } label: {
            Text(app.displayName)
                .font(.system(size: metrics.labelFont))
                .foregroundStyle(.white)
                // Two-line cap matches Finder's icon labels — longer names
                // are truncated with an ellipsis.
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: metrics.labelWidth)
        }
        .background {
            RoundedRectangle(cornerRadius: Search.selectionCornerRadius)
                .fill(.white.opacity(isSelected ? Search.selectionOpacity : 0))
                .padding(-metrics.iconSize * Search.selectionOutsetRatio)
        }
        .accessibilityIdentifier("app-icon")
        .accessibilityLabel(app.displayName)
        // `GridItemContainer` is a `VStack` + `onTapGesture`, not a `Button`,
        // so XCUI's `app.buttons` query wouldn't match it without this trait.
        // Adding `.isButton` also gives VoiceOver the correct semantic role.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // `@ViewBuilder` lets us return different concrete view types from the
    // two branches of `if/else`. Without it the compiler would complain that
    // `Image(nsImage:)` and `Image(systemName:)` have different generic
    // parameters even though both are `Image`.
    @ViewBuilder
    private var iconImage: some View {
        // Decoded once and cached — see `IconCache`.
        if let nsImage = IconCache.shared.image(for: app) {
            // `.resizable()` lets the image scale to fit `.frame(...)`. By
            // default, `Image` shows at its intrinsic (native) size — which
            // for a 128×128 PNG would always render at 128 pt regardless of
            // our `iconSize`.
            // `.interpolation(.high)` enables smooth downscaling for HiDPI.
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            // Defensive fallback — an app missing its iconData would render
            // as nothing without this. SF Symbol keeps the grid layout intact.
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
