import Foundation
import IOKit
import IOKit.pwr_mgt
import AppKit

// IOKit message constants (C macros that Swift does not import).
private let kMsgCanSystemSleep: UInt32 = 0xE000_0270
private let kMsgSystemWillSleep: UInt32 = 0xE000_0280
private let kMsgSystemHasPoweredOn: UInt32 = 0xE000_0300

/// Keeps the Mac awake while armed, wakes the display for warnings,
/// and can hold back sleep for a few seconds so the siren is audible when the lid is closed.
final class PowerManager {
    /// Called when the system is about to sleep. Call `allow` when it may proceed (it proceeds anyway after ~30 s).
    var onWillSleep: ((_ allow: @escaping () -> Void) -> Void)?
    var onDidWake: (() -> Void)?

    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var lidHelperFlag: String?

    init() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(ctx, &notifyPort, { ctx, _, messageType, argument in
            guard let ctx else { return }
            let me = Unmanaged<PowerManager>.fromOpaque(ctx).takeUnretainedValue()
            let token = Int(bitPattern: argument)
            switch messageType {
            case kMsgCanSystemSleep:
                IOAllowPowerChange(me.rootPort, token)
            case kMsgSystemWillSleep:
                var done = false
                let allow = {
                    guard !done else { return }
                    done = true
                    IOAllowPowerChange(me.rootPort, token)
                }
                if let handler = me.onWillSleep { handler(allow) } else { allow() }
            case kMsgSystemHasPoweredOn:
                me.onDidWake?()
            default:
                break
            }
        }, &notifier)
        if let notifyPort {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .commonModes)
        }
    }

    func beginArmed(keepDisplayOn: Bool) {
        endArmed()
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "StayPut theft protection is active" as CFString, &systemAssertion)
        if keepDisplayOn {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "StayPut lock screen" as CFString, &displayAssertion)
        }
    }

    func endArmed() {
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion); systemAssertion = 0 }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); displayAssertion = 0 }
    }

    /// Turns the display on (like touching the trackpad).
    func wakeDisplay() {
        var id: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity("StayPut warning" as CFString, kIOPMUserActiveLocal, &id)
        if id != 0 { IOPMAssertionRelease(id) }
    }

    // MARK: - Keep running with the lid closed

    /// Runs `pmset -a disablesleep 1` as root (asks for an admin password once).
    /// A root shell waits until StayPut disarms or quits and then turns sleep back on.
    /// Returns false if the user cancelled.
    @discardableResult
    func preventLidSleep() -> Bool {
        guard lidHelperFlag == nil else { return true }
        let flag = (NSTemporaryDirectory() as NSString).appendingPathComponent("stayput-\(getpid()).release")
        try? FileManager.default.removeItem(atPath: flag)
        let pid = getpid()
        let shell = """
        /usr/bin/pmset -a disablesleep 1
        while /bin/kill -0 \(pid) 2>/dev/null && [ ! -e '\(flag)' ]; do /bin/sleep 1; done
        /usr/bin/pmset -a disablesleep 0
        /bin/rm -f '\(flag)'
        """
        let b64 = Data(shell.utf8).base64EncodedString()
        let source = "do shell script \"/bin/echo \(b64) | /usr/bin/base64 -D | /bin/sh > /dev/null 2>&1 &\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard error == nil else { return false }
        lidHelperFlag = flag
        return true
    }

    func allowLidSleep() {
        guard let flag = lidHelperFlag else { return }
        FileManager.default.createFile(atPath: flag, contents: nil)
        lidHelperFlag = nil
    }
}
