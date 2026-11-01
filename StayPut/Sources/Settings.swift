import Foundation
import Combine
import Carbon.HIToolbox

/// A global keyboard shortcut (Carbon key code + Carbon modifier mask).
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let `default` = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_L),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⌃⌥⌘L"
    )
}

/// All user settings, stored in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    /// 1 (least sensitive) … 10 (most sensitive)
    @Published var sensitivity: Double { didSet { d.set(sensitivity, forKey: "sensitivity") } }
    @Published var soundEnabled: Bool { didSet { d.set(soundEnabled, forKey: "soundEnabled") } }
    /// 0 … 1
    @Published var volume: Double { didSet { d.set(volume, forKey: "volume") } }
    /// Seconds the siren plays before it stops by itself.
    @Published var alarmDuration: Double { didSet { d.set(alarmDuration, forKey: "alarmDuration") } }
    /// Unmute and set the Mac's output volume while the siren plays (restored afterwards).
    @Published var overrideSystemVolume: Bool { didSet { d.set(overrideSystemVolume, forKey: "overrideSystemVolume") } }
    /// Ask for Touch ID / password before disarming.
    @Published var requireAuth: Bool { didSet { d.set(requireAuth, forKey: "requireAuth") } }
    /// Seconds between activating and the start of monitoring.
    @Published var armDelay: Double { didSet { d.set(armDelay, forKey: "armDelay") } }
    @Published var keepDisplayOn: Bool { didSet { d.set(keepDisplayOn, forKey: "keepDisplayOn") } }
    /// Use `pmset disablesleep` (admin password) so the Mac keeps running with the lid closed.
    /// The App Store build can't run admin commands, so it leaves this option out.
    #if APPSTORE
    static let lidSleepOptionAvailable = false
    #else
    static let lidSleepOptionAvailable = true
    #endif
    @Published var preventLidSleep: Bool { didSet { d.set(preventLidSleep, forKey: "preventLidSleep") } }
    @Published var hotKey: HotKeyCombo {
        didSet { if let data = try? JSONEncoder().encode(hotKey) { d.set(data, forKey: "hotKey") } }
    }

    private init() {
        d.register(defaults: [
            "sensitivity": 5.0,
            "soundEnabled": true,
            "volume": 0.8,
            "alarmDuration": 30.0,
            "overrideSystemVolume": true,
            "requireAuth": true,
            "armDelay": 5.0,
            "keepDisplayOn": true,
            "preventLidSleep": false,
        ])
        sensitivity = d.double(forKey: "sensitivity")
        soundEnabled = d.bool(forKey: "soundEnabled")
        volume = d.double(forKey: "volume")
        alarmDuration = d.double(forKey: "alarmDuration")
        overrideSystemVolume = d.bool(forKey: "overrideSystemVolume")
        requireAuth = d.bool(forKey: "requireAuth")
        armDelay = d.double(forKey: "armDelay")
        keepDisplayOn = d.bool(forKey: "keepDisplayOn")
        preventLidSleep = d.bool(forKey: "preventLidSleep")
        if let data = d.data(forKey: "hotKey"), let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            hotKey = combo
        } else {
            hotKey = .default
        }
    }
}

/// Detection thresholds derived from the sensitivity setting.
struct Thresholds {
    let warnAccel: Double   // g (dynamic acceleration)
    let alarmAccel: Double  // g
    let warnTilt: Double    // degrees
    let alarmTilt: Double   // degrees
    let warnLid: Double     // degrees of display angle change

    init(sensitivity s: Double) {
        let k = (min(max(s, 1), 10) - 1) / 9 // 0 … 1
        warnAccel = 0.10 * pow(0.15, k)       // 0.100 g … 0.015 g
        alarmAccel = warnAccel * 4             // 0.40 g … 0.06 g
        warnTilt = 8 * pow(0.25, k)            // 8° … 2°
        alarmTilt = warnTilt * 3.5             // 28° … 7°
        warnLid = 10 * pow(0.3, k)             // 10° … 3°
    }
}
