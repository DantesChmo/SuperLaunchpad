import SwiftUI

// Dots at the bottom indicating the current page. Tap interactions are
// intentionally not wired (matches macOS Launchpad — the dots are passive).
struct PageIndicatorView: View {
    let totalPages: Int
    let currentPage: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            // `ForEach(0..<n, id: \.self)` — `Range<Int>` needs `id:` because
            // it isn't `Identifiable`. The index doubles as the stable id.
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 8, height: 8)
                    // 1.15× scaling makes the active dot stand out beyond
                    // just being opaque vs. semi-transparent.
                    .scaleEffect(index == currentPage ? 1.15 : 1.0)
                    .animation(Motion(reduced: reduceMotion).pageIndicatorAnimation, value: currentPage)
            }
        }
        // One element for VoiceOver: "Page 2 of 5" instead of a row of
        // unlabeled dots.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(totalPages)")
        .accessibilityIdentifier("page-indicator")
    }
}
