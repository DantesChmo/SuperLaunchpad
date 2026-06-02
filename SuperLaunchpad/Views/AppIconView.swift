import SwiftUI

struct AppIconView: View {
    let app: AppEntry
    let metrics: LayoutMetrics
    let onTap: () -> Void

    var body: some View {
        GridItemContainer(metrics: metrics, onTap: onTap) {
            iconImage
                .frame(width: metrics.iconSize, height: metrics.iconSize)
        } label: {
            Text(app.displayName)
                .font(.system(size: metrics.labelFont))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: metrics.labelWidth)
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        if let data = app.iconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
