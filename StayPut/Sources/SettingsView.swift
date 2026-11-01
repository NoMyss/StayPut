import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var controller: GuardController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Activate") {
                LabeledContent("Keyboard shortcut") {
                    ShortcutRecorder(combo: $settings.hotKey)
                }
                Text("The same shortcut turns protection on and off. You can also use the shield icon in the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Require Touch ID or password to turn off", isOn: $settings.requireAuth)
                LabeledContent("Start delay") {
                    Stepper("\(Int(settings.armDelay)) s", value: $settings.armDelay, in: 0...30, step: 1)
                }
                Toggle("Keep the lock screen visible (display stays on)", isOn: $settings.keepDisplayOn)
            }

            Section("Motion sensitivity") {
                HStack {
                    Text("Low").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $settings.sensitivity, in: 1...10, step: 1)
                    Text("High").font(.caption).foregroundStyle(.secondary)
                }
                MotionMeter(controller: controller, thresholds: Thresholds(sensitivity: settings.sensitivity))
                sensorStatus
                if !controller.motionAvailable {
                    Text("This Mac has no motion sensor, so StayPut can't protect it. StayPut needs a MacBook with Apple silicon (M1 or newer).")
                        .font(.caption).foregroundStyle(.red)
                }
            }

            Section("Alarm sound") {
                Toggle("Play a siren when the MacBook is moved a lot or closed", isOn: $settings.soundEnabled)
                Group {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $settings.volume, in: 0.1...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    LabeledContent("Siren stops after") {
                        Stepper("\(Int(settings.alarmDuration)) s", value: $settings.alarmDuration, in: 5...120, step: 5)
                    }
                    Toggle("Unmute the Mac and use this volume during the alarm", isOn: $settings.overrideSystemVolume)
                    Button("Test sound (2 s)") { controller.playTestSound() }
                        .disabled(controller.state != .idle)
                }
                .disabled(!settings.soundEnabled)
            }

            Section("Lid closed") {
                if Settings.lidSleepOptionAvailable {
                    Toggle("Keep running when the lid is closed (asks for admin password)", isOn: $settings.preventLidSleep)
                    Text("Without this, closing the lid starts the siren but macOS puts the Mac to sleep after up to about 25 seconds. With it, the Mac stays awake while protected and the siren plays for its full time. Sleep is turned back on when you turn protection off.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Closing the lid starts the siren. macOS puts the Mac to sleep after up to about 25 seconds, so the siren may stop early. Opening the lid again shows the warning.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Open StayPut at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 760)
        .onAppear { controller.acquireSensors() }
        .onDisappear { controller.releaseSensors(); controller.stopTestSound() }
    }

    @ViewBuilder private var sensorStatus: some View {
        HStack(spacing: 16) {
            status("Motion sensor", ok: controller.motionAvailable)
            status(controller.lidAngleAvailable ? "Lid angle sensor" : "Lid switch only", ok: true)
            if let angle = controller.lidAngle {
                Text("Display: \(Int(angle))°").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func status(_ name: String, ok: Bool) -> some View {
        Label(name, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.caption)
            .foregroundStyle(ok ? Color.green : Color.red)
    }
}

/// Live bar showing current movement against the warning and alarm thresholds.
struct MotionMeter: View {
    @ObservedObject var controller: GuardController
    let thresholds: Thresholds

    var body: some View {
        let scale = thresholds.alarmAccel * 1.25
        let level = min(controller.motionLevel / scale, 1)
        let warnX = thresholds.warnAccel / scale
        let alarmX = thresholds.alarmAccel / scale
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(controller.motionLevel > thresholds.alarmAccel ? Color.red
                              : controller.motionLevel > thresholds.warnAccel ? Color.orange : Color.green)
                        .frame(width: max(6, w * level))
                        .animation(.linear(duration: 0.1), value: level)
                    Rectangle().fill(Color.orange).frame(width: 2).offset(x: w * warnX)
                    Rectangle().fill(Color.red).frame(width: 2).offset(x: w * alarmX)
                }
            }
            .frame(height: 10)
            HStack {
                Text("Nudge the MacBook to try it. Orange line: screen warning. Red line: siren.")
                Spacer()
                Text("tilt \(controller.tiltDegrees, specifier: "%.1f")°").monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
