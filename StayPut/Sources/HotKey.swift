import AppKit
import Carbon.HIToolbox
import SwiftUI
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import OpenDirectory

/// Registers one system-wide keyboard shortcut (no Accessibility permission needed).
final class HotKeyManager {
    static let shared = HotKeyManager()
    var handler: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func register(_ combo: HotKeyCombo) {
        unregister()
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyManager.shared.handler?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x5354_5055), id: 1) // 'STPU'
        RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    /// Pause while the user records a new shortcut.
    func suspend() { unregister() }
    func resume() { register(Settings.shared.hotKey) }
}

/// A button that records a new keyboard shortcut when clicked.
struct ShortcutRecorder: View {
    @Binding var combo: HotKeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { recording ? stop() : start() }) {
                Text(recording ? "Type shortcut…" : combo.display)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 110)
            }
            if recording {
                Text("Esc to cancel").font(.caption).foregroundStyle(.secondary)
            } else if combo != .default {
                Button("Reset") { combo = .default }
                    .buttonStyle(.link)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == UInt16(kVK_Escape) && mods.isEmpty {
                stop()
                return nil
            }
            // Require at least one of ⌘ ⌥ ⌃ so normal typing never triggers it.
            guard !mods.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                return nil
            }
            combo = HotKeyCombo(keyCode: UInt32(event.keyCode),
                                modifiers: Self.carbonModifiers(mods),
                                display: Self.symbols(mods) + Self.keyName(event))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeyManager.shared.resume()
        }
    }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        if f.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }

    static func symbols(_ f: NSEvent.ModifierFlags) -> String {
        (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") +
        (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "")
    }

    static func keyName(_ e: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let s = special[Int(e.keyCode)] { return s }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

/// Checks the logged-in user's Mac password (no system dialog involved).
enum PasswordCheck {
    static func verify(_ password: String) -> Bool {
        guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes)),
              let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
        else { return false }
        do {
            try record.verifyPassword(password)
            return true
        } catch {
            return false
        }
    }
}

/// The Touch ID indicator embedded in StayPut's own window.
struct TouchIDView: NSViewRepresentable {
    let context: LAContext
    func makeNSView(context ctx: Context) -> LAAuthenticationView {
        LAAuthenticationView(context: context, controlSize: .small)
    }
    func updateNSView(_ view: LAAuthenticationView, context ctx: Context) {}
}
