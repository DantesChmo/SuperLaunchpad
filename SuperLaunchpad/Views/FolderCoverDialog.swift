import SwiftUI

// Change Cover… for a folder: an emoji typed or pasted into the field, or an
// image from a file panel. Drawn inside the launcher like the Trash dialog;
// the panel's key monitor leaves every key but Escape to the field.
struct FolderCoverDialog: View {
    let folder: FolderEntry
    let customIcons: CustomIconModel

    @State private var text = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(Uninstall.dialogDimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { customIcons.cancelCoverEdit() }
                .accessibilityHidden(true)

            VStack(spacing: Uninstall.dialogSpacing) {
                Text("Cover for “\(folder.title)”")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                TextField("Emoji", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: CustomIcons.dialogEmojiFontSize))
                    .multilineTextAlignment(.center)
                    .frame(width: CustomIcons.dialogEmojiFieldWidth)
                    .focused($isFieldFocused)
                    .onSubmit { customIcons.setCoverEmoji(text) }
                    .accessibilityIdentifier("folder-cover-emoji")
                Text("Type or paste an emoji, or choose an image.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose Image…") {
                    customIcons.chooseCoverImage()
                }
                HStack {
                    Button {
                        customIcons.cancelCoverEdit()
                    } label: {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        customIcons.setCoverEmoji(text)
                    } label: {
                        Text("Use Emoji").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(FolderCover.emoji(from: text) == nil)
                }
                .controlSize(.large)
            }
            .padding(Uninstall.dialogPadding)
            .frame(width: Uninstall.dialogWidth)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Uninstall.dialogCornerRadius))
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("folder-cover-dialog")
        }
        .onAppear {
            text = folder.coverEmoji ?? ""
            isFieldFocused = true
        }
    }
}
