import AppKit
import SwiftUI

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen lock windows on every display, plus "kiosk" presentation options
/// (no Dock, menu bar, ⌘-Tab, Force Quit or log-out while armed).
final class OverlayController {
    private unowned let controller: GuardController
    private var windows: [NSWindow] = []
    private var screenObserver: Any?
    private var inputMonitor: Any?

    private static let kiosk: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit,
        .disableSessionTermination, .disableHideApplication, .disableAppleMenu,
    ]

    init(controller: GuardController) {
        self.controller = controller
    }

    func show() {
        buildWindows()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = Self.kiosk
        windows.first?.makeKeyAndOrderFront(nil)
        installInputMonitor()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, !self.windows.isEmpty else { return }
                self.buildWindows()
                self.controller.startTouchID() // its view was recreated
            }
        }
    }

    func hide() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        NSApp.presentationOptions = []
    }

    /// Make the main lock window take keyboard input (for the password field).
    func focus() {
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
    }

    /// With Touch ID / password required, any key or click on the lock screen opens the
    /// unlock panel, like the macOS lock screen. A fallback in case the shortcut doesn't arrive.
    private func installInputMonitor() {
        guard inputMonitor == nil else { return }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, !self.windows.isEmpty else { return event }
            let c = self.controller
            if c.settings.requireAuth, c.state.isArmed, !c.unlockPanelVisible {
                c.showUnlockPanel()
                return event.type == .keyDown ? nil : event
            }
            return event
        }
    }

    private func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        for (index, screen) in NSScreen.screens.enumerated() {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: true)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.canBecomeVisibleWithoutLogin = true
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OverlayView(controller: controller, settings: .shared, isPrimary: index == 0))
            w.orderFrontRegardless()
            windows.append(w)
        }
    }
}

// MARK: - Lock screen UI

struct OverlayView: View {
    @ObservedObject var controller: GuardController
    @ObservedObject var settings: Settings
    var isPrimary = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let flash = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            ZStack {
                background(flash: flash).ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    content(date: context.date)
                    Spacer()
                    if isPrimary && controller.unlockPanelVisible {
                        UnlockPanel(controller: controller)
                            .padding(.bottom, 24)
                    }
                    footer
                }
                .padding(48)
            }
        }
    }

    private var palette: (bg: Color, fg: Color) {
        switch controller.state {
        case .warning: return (Color(red: 0.98, green: 0.69, blue: 0.13), Color(red: 0.10, green: 0.07, blue: 0.0))
        case .alarm: return (Color(red: 0.86, green: 0.10, blue: 0.17), .white)
        default: return (Color(red: 0.05, green: 0.06, blue: 0.08), .white)
        }
    }

    @ViewBuilder private func background(flash: Bool) -> some View {
        switch controller.state {
        case .alarm:
            (flash ? palette.bg : Color(red: 0.35, green: 0.02, blue: 0.05))
        case .warning:
            palette.bg
        default:
            LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.11), Color(red: 0.02, green: 0.02, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder private func content(date: Date) -> some View {
        let fg = palette.fg
        VStack(spacing: 22) {
            switch controller.state {
            case .idle:
                EmptyView()
            case .arming(let s):
                Image(systemName: "lock.shield")
                    .font(.system(size: 80, weight: .light))
                Text("Protection starts in \(s)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Place the MacBook where you want to leave it and step away.")
                    .font(.title2).opacity(0.7)
            case .locked:
                Text(date, format: .dateTime.hour().minute())
                    .font(.system(size: 110, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Label("This MacBook is protected", systemImage: "lock.shield.fill")
                    .font(.system(size: 30, weight: .semibold))
                Text("Movement, the lid and the display angle are monitored.\nMoving it will sound an alarm.")
                    .multilineTextAlignment(.center)
                    .font(.title2).opacity(0.65)
            case .warning(let reason):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 96))
                Text("Please don't move this MacBook")
                    .font(.system(size: 52, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("\(reason) This MacBook is protected against theft.\nMoving it further will sound an alarm.")
                    .multilineTextAlignment(.center)
                    .font(.title).opacity(0.85)
            case .alarm(let reason):
                Image(systemName: "light.beacon.max.fill")
                    .font(.system(size: 110))
                Text("THEFT ALARM")
                    .font(.system(size: 88, weight: .black))
                    .kerning(4)
                Text("\(reason)\nThis MacBook is protected. Put it back now.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 30, weight: .semibold))
            }
        }
        .foregroundStyle(fg)
    }

    @ViewBuilder private var footer: some View {
        ZStack {
            HStack {
                Text("StayPut").font(.headline).opacity(0.4)
                Spacer()
                if settings.requireAuth {
                    Button {
                        controller.showUnlockPanel()
                    } label: {
                        Label("Use password", systemImage: "key.fill")
                            .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(.white.opacity(0.12), in: Capsule())
                    .focusable(false) // no blue focus ring when the lock screen appears
                }
            }
            // Touch ID is always listening: the owner just touches the sensor.
            if isPrimary, settings.requireAuth, let ctx = controller.touchIDContext {
                VStack(spacing: 8) {
                    ZStack {
                        // The real Touch ID view only comes in fixed sizes (32 or 64 pt) and
                        // cropping/scaling it breaks it, so it sits underneath a 48 pt glyph.
                        TouchIDView(context: ctx)
                            .frame(width: 32, height: 32)
                        Image(systemName: "touchid")
                            .font(.system(size: 40, weight: .regular))
                            .foregroundStyle(Color(red: 0.93, green: 0.30, blue: 0.40))
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color(red: 0.04, green: 0.04, blue: 0.05)))
                    }
                        .id(ObjectIdentifier(ctx))
                    Text("Touch ID to unlock").font(.headline).opacity(0.85)
                }
            }
        }
        .foregroundStyle(palette.fg)
    }
}

/// Touch ID + password, shown on the lock screen when the owner wants to unlock.
struct UnlockPanel: View {
    @ObservedObject var controller: GuardController
    @State private var password = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text("Unlock StayPut").font(.title2.weight(.semibold))
            Text(controller.touchIDContext != nil
                 ? "Enter your Mac password, or just touch Touch ID."
                 : "Enter your Mac password.")
                .font(.callout).opacity(0.8)
            HStack(spacing: 10) {
                SecureField("Mac password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                Button("Unlock", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || controller.checkingPassword)
            }
            if let error = controller.unlockError {
                Text(error).font(.callout.weight(.semibold)).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.55))
            }
            Button("Cancel") { controller.hideUnlockPanel() }
                .buttonStyle(.link)
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 440)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
        .onChange(of: controller.unlockError) { e in if e != nil { password = ""; fieldFocused = true } }
    }

    private func submit() {
        controller.submitPassword(password)
    }
}
