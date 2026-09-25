import AppKit

enum Setting: Equatable {
    case off
    case sub(Int)
    case normal(Float)

    static let subSpan = 0.3

    init(position p: Double) {
        let p = min(max(p, 0), 1)
        if p <= 0.001 {
            self = .off
        } else if p <= Setting.subSpan {
            self = .sub(max(1, min(Dimmer.subSteps, Int((p / Setting.subSpan * Double(Dimmer.subSteps)).rounded()))))
        } else {
            let t = (p - Setting.subSpan) / (1 - Setting.subSpan)
            self = .normal(Backlight.floorBrightness + (1 - Backlight.floorBrightness) * Float(t * t))
        }
    }

    var position: Double {
        switch self {
        case .off: return 0
        case .sub(let step): return Double(step) / Double(Dimmer.subSteps) * Setting.subSpan
        case .normal(let b):
            let t = Double(max(0, (b - Backlight.floorBrightness) / (1 - Backlight.floorBrightness))).squareRoot()
            return Setting.subSpan + t * (1 - Setting.subSpan) + 0.0001
        }
    }

    var label: String {
        switch self {
        case .off: return "Off"
        case .sub(let step): return "Below minimum \(step)/\(Dimmer.subSteps)"
        case .normal(let b): return "\(max(1, Int((b * 100).rounded())))%"
        }
    }
}

// macOS clamps nonzero brightness to a PWM floor, but fades interpolate the raw duty
// all the way to 0. Fade down, read the live duty, and hold it with slow fades.
final class Dimmer {
    static let subSteps = 10

    private static let stepFractions: [Double] = [2, 4, 7, 11, 15, 20, 26, 32, 39, 46].map { $0 / 54 }

    private static let approachMs = 400.0
    private static let slowestFadeMs = 65_535

    private enum Motion { case none, fastDown, fastUp, slowDown }

    private let backlight: Backlight
    private(set) var setting: Setting = .off
    var onUserTakeover: ((Setting) -> Void)?

    private var timer: Timer?
    private var motion: Motion = .none
    private var lastTarget = Backlight.floorBrightness
    private var targetDuty = 0
    private var suspended = false

    private var floorDuty = UserDefaults.standard.object(forKey: "floorDuty") as? Int ?? 54 {
        didSet { UserDefaults.standard.set(floorDuty, forKey: "floorDuty") }
    }
    private var needsFloorReading = false
    private var floorCandidate: Int?

    init(backlight: Backlight) {
        self.backlight = backlight
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.suspend(true)
        }
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.suspend(true)
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspend(false)
            }
        }
    }

    var systemSetting: Setting {
        let b = backlight.brightness
        return b <= 0 ? .off : .normal(max(b, Backlight.floorBrightness))
    }

    func apply(_ new: Setting) {
        let wasSub: Bool
        if case .sub = setting { wasSub = true } else { wasSub = false }
        setting = new

        switch new {
        case .off:
            stop()
            backlight.set(0)
        case .normal(let b):
            stop()
            backlight.set(b)
        case .sub(let step):
            if !wasSub {
                backlight.set(Backlight.floorBrightness)
                needsFloorReading = true
                floorCandidate = nil
                lastTarget = Backlight.floorBrightness
                motion = .none
            }
            targetDuty = duty(for: step)
            if timer == nil { schedule(0.25) }
        }
    }

    func releaseToFloor() {
        if case .sub = setting { backlight.set(Backlight.floorBrightness) }
        stop()
    }

    private func duty(for step: Int) -> Int {
        let fraction = Dimmer.stepFractions[max(0, min(Dimmer.subSteps - 1, step - 1))]
        return max(2, min(floorDuty - 1, Int((fraction * Double(floorDuty)).rounded())))
    }

    private func suspend(_ on: Bool) {
        suspended = on
        guard case .sub = setting else { return }
        if on {
            timer?.invalidate()
            timer = nil
        } else {
            motion = .none
            schedule(0.5)
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        motion = .none
    }

    private func schedule(_ seconds: TimeInterval) {
        timer?.invalidate()
        guard !suspended else { timer = nil; return }
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.tick() }
        t.tolerance = seconds * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        timer = nil
        guard case .sub(let step) = setting else { return }

        let stored = backlight.brightness
        if abs(stored - lastTarget) > 0.0001 && abs(stored - Backlight.floorBrightness) > 0.0001 {
            let taken: Setting = stored <= 0 ? .off : .normal(stored)
            setting = taken
            stop()
            onUserTakeover?(taken)
            return
        }

        guard let d = backlight.duty else {
            if (motion == .fastDown || motion == .slowDown) && !backlight.isIdleDimmed {
                fade(.fastUp, to: Backlight.floorBrightness, ms: 1_000)
                schedule(0.1)
            } else {
                motion = .none
                schedule(0.5)
            }
            return
        }

        if needsFloorReading {
            guard d == floorCandidate else {
                floorCandidate = d
                schedule(0.15)
                return
            }
            needsFloorReading = false
            floorDuty = d
            targetDuty = duty(for: step)
        }

        let err = d - targetDuty
        if err > 0 {
            let ms = Int(Dimmer.approachMs * Double(d) / Double(err))
            fade(.fastDown, to: 0, ms: ms)
            schedule(0.1)
        } else if err < 0 {
            let span = max(1, floorDuty - d)
            let ms = Int(Dimmer.approachMs * Double(span) / Double(-err))
            fade(.fastUp, to: Backlight.floorBrightness, ms: ms)
            schedule(0.1)
        } else {
            if motion != .slowDown { fade(.slowDown, to: 0, ms: Dimmer.slowestFadeMs) }
            schedule(0.3)
        }
    }

    // A fade toward the target already being faded to is ignored, so brake first.
    private func fade(_ m: Motion, to value: Float, ms: Int) {
        if value == lastTarget && motion != .none {
            let away: Float = value == 0 ? Backlight.floorBrightness : 0
            backlight.fade(to: away, ms: Dimmer.slowestFadeMs, commit: false)
        }
        backlight.fade(to: value, ms: min(max(ms, 20), Dimmer.slowestFadeMs), commit: false)
        motion = m
        lastTarget = value
    }
}
