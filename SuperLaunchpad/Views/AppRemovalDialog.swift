import SwiftUI

// Asks before an app goes to the Trash, or says why it can't. Drawn inside
// the launcher: an `NSAlert` would open below its `.screenSaver`-level panel.
// Escape and Return reach the view model through the panel's key monitor.
struct AppRemovalDialog: View {
    let removal: LaunchpadViewModel.PendingRemoval
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(Uninstall.dialogDimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)

            VStack(spacing: Uninstall.dialogSpacing) {
                if let icon = IconCache.shared.image(for: removal.app) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: Uninstall.dialogIconSize, height: Uninstall.dialogIconSize)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if removal.stage == .quitting {
                    ProgressView()
                        .controlSize(.small)
                }
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buttons
            }
            .padding(Uninstall.dialogPadding)
            .frame(width: Uninstall.dialogWidth)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Uninstall.dialogCornerRadius))
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("app-removal-dialog")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            switch removal.stage {
            case .confirm, .appIsOpen:
                Button(action: onCancel) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive, action: onConfirm) {
                    Text(removal.stage == .confirm ? "Move to Trash" : "Quit and Move").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            case .quitting:
                Button(action: onCancel) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            case .didNotQuit, .failed:
                Button(action: onConfirm) {
                    Text("OK").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
    }

    private var name: String {
        removal.app.displayName
    }

    private var title: String {
        switch removal.stage {
        case .confirm:
            String(localized: "Move “\(name)” to the Trash?")
        case .appIsOpen:
            String(localized: "“\(name)” is open")
        case .quitting:
            String(localized: "Quitting “\(name)”…")
        case .didNotQuit:
            String(localized: "“\(name)” didn’t quit")
        case .failed:
            String(localized: "Couldn’t move “\(name)” to the Trash")
        }
    }

    private var message: String? {
        switch removal.stage {
        case .confirm:
            nil
        case .appIsOpen:
            String(localized: "Quit it and move it to the Trash?")
        case .quitting:
            nil
        case .didNotQuit:
            String(localized: "It may be asking to save changes. Quit it yourself, then move it to the Trash.")
        case .failed(.finderNotPermitted):
            String(localized: "Allow SuperLaunchpad to control Finder in System Settings → Privacy & Security → Automation.")
        case .failed(.other(let reason)):
            reason.isEmpty ? nil : reason
        case .failed(.cancelled):
            nil
        }
    }
}
