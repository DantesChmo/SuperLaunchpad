import SwiftUI

struct PageIndicatorView: View {
    let totalPages: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == currentPage ? 1.15 : 1.0)
                    .animation(.spring(duration: 0.3, bounce: 0.2), value: currentPage)
            }
        }
    }
}
