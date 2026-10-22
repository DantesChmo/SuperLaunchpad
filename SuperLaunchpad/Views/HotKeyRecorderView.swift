import Carbon.HIToolbox
import SwiftUI

struct HotKeyRecorderView: View {
    let hotKeyMonitor: HotKeyMonitor

    @State private var combo = Preferences().hotKey
    @State private var isRecording = false
    @State private var needsModifier = false
    @State private var keyMonitor: Any?

    var body: some View {
        LabeledContent("Show / Hide launcher") {
            Button(buttonTitle) {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
        }
        .onDisappear(perform: stopRecording)
        if isRecording {
            Text(needsModifier
                 ? "Use at least one of ⌘, ⌥ or ⌃."
                 : "Press Esc to cancel, Delete to remove the shortcut.")
                .font(.callout)
                .foregroundStyle(needsModifier ? Color.red : Color.secondary)
        } else if hotKeyMonitor.registrationFailed {
            Text("This shortcut is used by another app. Choose a different one.")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private var buttonTitle: String {
        if isRecording { return "Type shortcut…" }
        return combo?.displayString ?? "None"
    }

    private func startRecording() {
        guard keyMonitor == nil else { return }
        needsModifier = false
        isRecording = true
        hotKeyMonitor.isPaused = true
        // Returning nil swallows the key, including menu key equivalents like ⌘Q.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        isRecording = false
        hotKeyMonitor.isPaused = false
    }

    private func handle(_ event: NSEvent) {
        let candidate = KeyCombo(event: event)
        let hasModifiers = candidate.modifiers != 0
        switch Int(event.keyCode) {
        case kVK_Escape where !hasModifiers:
            stopRecording()
        case kVK_Delete where !hasModifiers, kVK_ForwardDelete where !hasModifiers:
            save(nil)
        default:
            guard candidate.isValidHotKey else {
                needsModifier = true
                return
            }
            save(candidate)
        }
    }

    private func save(_ newCombo: KeyCombo?) {
        combo = newCombo
        Preferences().hotKey = newCombo
        stopRecording()
    }
}
