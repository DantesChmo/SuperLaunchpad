import SwiftUI

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
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .frame(width: 200)
    }
}
