import Foundation
import IOKit
import IOKit.hid

/// Reads the built-in accelerometer of Apple Silicon MacBooks.
/// It is exposed by the "AppleSPUHIDDevice" HID service (vendor usage page 0xFF00, usage 3).
/// Each 22-byte report holds X/Y/Z as little-endian Int32 at offsets 6/10/14, in units of 1/65536 g.
final class MotionSensor {
    var onSample: ((SIMD3<Double>) -> Void)?
    private(set) var isRunning = false

    private var manager: IOHIDManager?
    private var devices: [IOHIDDevice] = []
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private static let reportSize = 64

    /// True if this Mac has a readable accelerometer.
    static var isAvailable: Bool {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(m, matching)
        guard IOHIDManagerOpen(m, 0) == kIOReturnSuccess else { return false }
        defer { IOHIDManagerClose(m, 0) }
        return ((IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>)?.isEmpty == false)
    }

    private static var matching: CFDictionary {
        [kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 3, kIOHIDTransportKey: "SPU"] as CFDictionary
    }

    @discardableResult
    func start() -> Bool {
        stop()
        Self.enableDriver()
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(m, Self.matching)
        guard IOHIDManagerOpen(m, 0) == kIOReturnSuccess,
              let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>, !set.isEmpty else {
            return false
        }
        manager = m
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        for dev in set {
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportSize)
            buffers.append(buf)
            devices.append(dev)
            IOHIDDeviceRegisterInputReportCallback(dev, buf, Self.reportSize, { ctx, _, _, _, _, report, length in
                guard let ctx, length >= 18 else { return }
                func axis(_ o: Int) -> Double {
                    let raw = UInt32(report[o]) | UInt32(report[o + 1]) << 8 | UInt32(report[o + 2]) << 16 | UInt32(report[o + 3]) << 24
                    return Double(Int32(bitPattern: raw)) / 65536.0
                }
                let me = Unmanaged<MotionSensor>.fromOpaque(ctx).takeUnretainedValue()
                me.onSample?(SIMD3(axis(6), axis(10), axis(14)))
            }, ctx)
            IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        isRunning = true
        return true
    }

    func stop() {
        for (dev, buf) in zip(devices, buffers) {
            IOHIDDeviceRegisterInputReportCallback(dev, buf, Self.reportSize, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        if let manager { IOHIDManagerClose(manager, 0) }
        manager = nil
        devices.removeAll()
        buffers.forEach { $0.deallocate() }
        buffers.removeAll()
        isRunning = false
    }

    /// Ask the sensor driver to power on and report at 100 Hz.
    private static func enableDriver() {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }
            let page = IORegistryEntryCreateCFProperty(service, "PrimaryUsagePage" as CFString, nil, 0)?.takeRetainedValue() as? Int
            let usage = IORegistryEntryCreateCFProperty(service, "PrimaryUsage" as CFString, nil, 0)?.takeRetainedValue() as? Int
            guard page == 0xFF00, usage == 3 else { continue }
            IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "ReportInterval" as CFString, 10_000 as CFNumber) // µs → 100 Hz
        }
    }
}

/// Reads the lid (display hinge) angle sensor found on recent MacBooks
/// (HID usage page 0x20 "Sensors", usage 0x8A). Falls back to the clamshell switch.
final class LidSensor {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    var hasAngleSensor: Bool { device != nil }

    func start() {
        guard manager == nil else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(m, [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDPrimaryUsagePageKey: 0x20,
            kIOHIDPrimaryUsageKey: 0x8A,
        ] as CFDictionary)
        guard IOHIDManagerOpen(m, 0) == kIOReturnSuccess else { return }
        manager = m
        if let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> {
            device = set.first(where: { Self.read($0) != nil })
        }
    }

    func stop() {
        if let manager { IOHIDManagerClose(manager, 0) }
        manager = nil
        device = nil
    }

    /// Current display angle in degrees (0 = closed), or nil if the sensor is missing.
    func angle() -> Double? {
        guard let device else { return nil }
        return Self.read(device)
    }

    private static func read(_ dev: IOHIDDevice) -> Double? {
        var buf = [UInt8](repeating: 0, count: 8)
        var len = CFIndex(buf.count)
        guard IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 1, &buf, &len) == kIOReturnSuccess, len >= 3 else { return nil }
        return Double(UInt16(buf[1]) | UInt16(buf[2]) << 8)
    }

    /// The hardware lid switch (works on every MacBook).
    static func clamshellClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, nil, 0)?.takeRetainedValue() as? Bool
    }
}
