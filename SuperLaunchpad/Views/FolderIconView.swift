import SwiftUI

struct FolderIconView: View {
    let folder: FolderEntry
    let apps: [AppEntry]
    let metrics: LayoutMetrics
    let onTap: () -> Void

    private let previewColumns = 3
    private let previewRows = 3

    var body: some View {
        GridItemContainer(metrics: metrics, onTap: onTap) {
            folderIcon
                .frame(width: metrics.iconSize, height: metrics.iconSize)
        } label: {
            Text(folder.title)
                .font(.system(size: metrics.labelFont))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: metrics.labelWidth)
        }
    }

    private var folderIcon: some View {
        let miniSize = metrics.iconSize * 0.22
        let spacing = metrics.iconSize * 0.06
        let previewApps = Array(apps.prefix(previewColumns * previewRows))

        return RoundedRectangle(cornerRadius: metrics.iconSize * 0.2)
            .fill(.white.opacity(0.15))
            .overlay(
                VStack(spacing: spacing) {
                    ForEach(0..<previewRows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<previewColumns, id: \.self) { col in
                                let index = row * previewColumns + col
                                if index < previewApps.count,
                                   let data = previewApps[index].iconData,
                                   let nsImage = NSImage(data: data) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: miniSize, height: miniSize)
                                        .clipShape(RoundedRectangle(cornerRadius: miniSize * 0.2))
                                } else if index < previewApps.count {
                                    RoundedRectangle(cornerRadius: miniSize * 0.2)
                                        .fill(.white.opacity(0.2))
                                        .frame(width: miniSize, height: miniSize)
                                } else {
                                    Color.clear
                                        .frame(width: miniSize, height: miniSize)
                                }
                            }
                        }
                    }
                }
                .padding(metrics.iconSize * 0.1)
            )
    }
}
