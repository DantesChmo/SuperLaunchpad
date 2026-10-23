import SwiftUI

// Asks before an app goes to the Trash, or says why it can't. Drawn inside
// the launcher: an `NSAlert` would open below its `.screenSaver`-level panel.
// Escape and Return reach the view model through the panel's key monitor.
// A group (multi-select) gets one dialog with its icons side by side.
struct AppRemovalDialog: View {
    let removal: RemovalModel.PendingRemoval
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
                HStack(spacing: -Uninstall.dialogIconSize * Uninstall.groupIconOverlap) {
                    ForEach(removal.apps.prefix(Uninstall.groupIconCount)) { app in
                        if let icon = IconCache.shared.image(for: app) {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: Uninstall.dialogIconSize, height: Uninstall.dialogIconSize)
                        }
                    }
                }
                .accessibilityHidden(true)
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
        if removal.isGroup, let groupTitle {
            return groupTitle
        }
        return switch removal.stage {
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

    // A group's title, for the stages that name the apps; a failure names
    // the one app that failed.
    private var groupTitle: String? {
        let count = removal.apps.count
        return switch removal.stage {
        case .confirm: String(localized: "Move \(count) apps to the Trash?")
        case .appIsOpen: String(localized: "Some of these apps are open")
        case .quitting: String(localized: "Quitting apps…")
        case .didNotQuit: String(localized: "Not every app quit")
        case .failed: nil
        }
    }

    private var groupMessage: String? {
        switch removal.stage {
        case .confirm:
            [names, skippedNote].compactMap { $0 }.joined(separator: "\n")
        case .appIsOpen:
            [String(localized: "Quit them and move all \(removal.apps.count) to the Trash?"), skippedNote].compactMap { $0 }.joined(separator: "\n")
        case .quitting:
            nil
        case .didNotQuit:
            String(localized: "One may be asking to save changes. Quit it yourself, then try again.")
        case .failed:
            nil
        }
    }

    private var names: String {
        ListFormatter.localizedString(byJoining: removal.apps.map(\.displayName))
    }

    private var skippedNote: String? {
        switch removal.skippedCount {
        case 0: nil
        case 1: String(localized: "1 app that is part of macOS stays.")
        default: String(localized: "\(removal.skippedCount) apps that are part of macOS stay.")
        }
    }

    private var message: String? {
        if removal.isGroup, !isFailure {
            return groupMessage
        }
        return switch removal.stage {
        case .confirm:
            skippedNote
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

    private var isFailure: Bool {
        if case .failed = removal.stage { return true }
        return false
    }
}
