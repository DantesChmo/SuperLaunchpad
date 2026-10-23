import SwiftUI

struct SettingsView: View {
    let hotKeyMonitor: HotKeyMonitor
    @Bindable var updater: UpdaterController
    let viewModel: LaunchpadViewModel

    @AppStorage(Preferences.Key.pinchGestureEnabled)
    private var pinchGestureEnabled = Preferences.Default.pinchGestureEnabled

    @AppStorage(Preferences.Key.newAppPlacement)
    private var newAppPlacement = Preferences.Default.newAppPlacement

    @AppStorage(Preferences.Key.showsFrequentApps)
    private var showsFrequentApps = Preferences.Default.showsFrequentApps

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

            Section("New Apps") {
                Picker("Put new apps", selection: $newAppPlacement) {
                    ForEach(NewAppPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                Group {
                    if newAppPlacement == .categoryFolder {
                        Text("New apps have a blue dot until you open them from SuperLaunchpad. An app goes at the end when no folder is named after its category.")
                    } else {
                        Text("New apps have a blue dot until you open them from SuperLaunchpad.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Search") {
                Toggle("Show frequently used apps above the grid", isOn: $showsFrequentApps)
                Text("Search lists the apps you open most often first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard") {
                HotKeyRecorderView(hotKeyMonitor: hotKeyMonitor)
            }

            Section {
                if viewModel.hiddenApps.isEmpty {
                    Text("No hidden apps.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.hiddenApps) { app in
                        HiddenAppRow(app: app) {
                            viewModel.unhideApp(app.bundleIdentifier)
                        }
                    }
                }
            } header: {
                Text("Hidden Apps")
            } footer: {
                Text("Hide an app from its context menu. Hidden apps can still be found by search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                if updater.isAvailable {
                    Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                } else {
                    Text("Updates are not available in this build.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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

private struct HiddenAppRow: View {
    let app: AppEntry
    let onUnhide: () -> Void

    var body: some View {
        HStack {
            Group {
                if let icon = IconCache.shared.image(for: app) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: SettingsWindow.hiddenAppIconSize, height: SettingsWindow.hiddenAppIconSize)
            .accessibilityHidden(true)
            Text(app.displayName)
            Spacer()
            Button("Unhide", action: onUnhide)
                .accessibilityLabel("Unhide \(app.displayName)")
        }
    }
}
