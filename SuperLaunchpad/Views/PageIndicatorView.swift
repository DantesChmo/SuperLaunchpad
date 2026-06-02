import SwiftUI

// Dots at the bottom indicating the current page. Tap interactions are
// intentionally not wired (matches macOS Launchpad — the dots are passive).
struct PageIndicatorView: View {
    let totalPages: Int
    let currentPage: Int

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
                    .animation(.spring(duration: 0.3, bounce: 0.2), value: currentPage)
            }
        }
    }
}
