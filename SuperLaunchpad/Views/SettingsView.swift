import SwiftUI

struct SettingsView: View {
    let hotKeyMonitor: HotKeyMonitor

    @AppStorage(Preferences.Key.pinchGestureEnabled)
    private var pinchGestureEnabled = Preferences.Default.pinchGestureEnabled

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemNeedsApproval = LoginItem.requiresApproval
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if loginItemNeedsApproval {
                    Text("Allow SuperLaunchpad in Login Items to finish enabling.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if loginItemNeedsApproval || loginItemError != nil {
                    Button("Open Login Items Settings…") {
                        LoginItem.openSystemSettings()
                    }
                }
            }

            Section("Gestures") {
                Toggle("Pinch to open/close", isOn: $pinchGestureEnabled)
                Text("macOS 26 may also handle the pinch gesture itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard") {
                HotKeyRecorderView(hotKeyMonitor: hotKeyMonitor)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindow.width)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshLoginItem)
        // The user may approve or remove the login item in System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItem()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { setLaunchAtLogin($0) }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        launchAtLogin = LoginItem.isEnabled || LoginItem.requiresApproval
        loginItemNeedsApproval = LoginItem.requiresApproval
    }
}
