import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private lazy var guardController = GuardController.shared
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        HotKeyManager.shared.handler = { [weak self] in self?.guardController.toggle() }
        HotKeyManager.shared.register(settings.hotKey)
        settings.$hotKey.dropFirst().sink { HotKeyManager.shared.register($0) }.store(in: &cancellables)
        guardController.$state.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        updateIcon()

        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            openSettings()
        }
        if ProcessInfo.processInfo.environment["STAYPUT_ARM_ON_LAUNCH"] != nil {
            guardController.arm()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quitting must not be a way around the protection.
        guardController.state.isArmed ? .terminateCancel : .terminateNow
    }

    private func updateIcon() {
        let armed = guardController.state.isArmed
        let image = NSImage(systemSymbolName: armed ? "lock.shield.fill" : "lock.shield",
                            accessibilityDescription: armed ? "StayPut: protected" : "StayPut")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let armed = guardController.state.isArmed
        let toggle = NSMenuItem(title: armed ? "Turn Off Protection" : "Protect This MacBook",
                                action: #selector(toggleProtection), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let hint = NSMenuItem(title: "Shortcut: \(settings.hotKey.display)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        if !guardController.motionAvailable {
            let warn = NSMenuItem(title: "No motion sensor: StayPut needs a MacBook", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        let quit = NSMenuItem(title: "Quit StayPut", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleProtection() { guardController.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, controller: guardController))
            let w = NSWindow(contentViewController: hosting)
            w.title = "StayPut Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        // Rebuild content each time so the sensors start/stop with the window.
        settingsWindow?.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, controller: guardController))
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
