import Foundation
import IOKit

final class Backlight {
    static let floorBrightness: Float = 0.001
    static let slowestFadeMs = 65_535

    private typealias GetF = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias GetD = @convention(c) (AnyObject, Selector, UInt64) -> Double
    private typealias SetFade = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool

    private let client: NSObject
    private let keyboard: UInt64
    private let getBrightness: GetF
    private let setFade: SetFade
    private let getIdleDimTime: GetD
    private let pwm: io_service_t
    private(set) var lastTarget: Float = 0

    private let selBrightness = NSSelectorFromString("brightnessForKeyboard:")
    private let selFade = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
    private let selIdleDimTime = NSSelectorFromString("idleDimTimeForKeyboard:")

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let client = cls.init()
        guard let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?
                .takeRetainedValue() as? [NSNumber],
              let first = ids.first,
              client.responds(to: selBrightness), client.responds(to: selFade),
              client.responds(to: selIdleDimTime) else { return nil }
        let pwm = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("kbd-backlight"))
        guard pwm != 0 else { return nil }

        self.client = client
        self.keyboard = first.uint64Value
        self.getBrightness = unsafeBitCast(client.method(for: selBrightness), to: GetF.self)
        self.setFade = unsafeBitCast(client.method(for: selFade), to: SetFade.self)
        self.getIdleDimTime = unsafeBitCast(client.method(for: selIdleDimTime), to: GetD.self)
        self.pwm = pwm
        self.lastTarget = brightness
    }

    deinit { IOObjectRelease(pwm) }

    var brightness: Float { getBrightness(client, selBrightness, keyboard) }

    // A fade toward the target already being faded to is ignored, so brake first.
    func fade(to value: Float, ms: Int, commit: Bool) {
        if value == lastTarget {
            let away: Float = value == 0 ? Backlight.floorBrightness : 0
            _ = setFade(client, selFade, away, Int32(Backlight.slowestFadeMs), false, keyboard)
        }
        _ = setFade(client, selFade, value, Int32(clamping: ms), commit, keyboard)
        lastTarget = value
    }

    func set(_ value: Float) { fade(to: value, ms: 0, commit: true) }

    var duty: Int? {
        guard (property("enabled") as? Bool) == true,
              let high = (property("high-period") as? NSNumber)?.intValue else { return nil }
        return high
    }

    var isIdleDimmed: Bool {
        let hid = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        defer { IOObjectRelease(hid) }
        guard hid != 0,
              let ns = IORegistryEntryCreateCFProperty(hid, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber else { return false }
        let dimAfter = getIdleDimTime(client, selIdleDimTime, keyboard)
        return dimAfter > 0 && ns.doubleValue / 1e9 >= dimAfter - 1
    }

    private func property(_ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(pwm, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
