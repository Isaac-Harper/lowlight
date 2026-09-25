import AppKit

if CommandLine.arguments.contains("--enable-login") ||
   CommandLine.arguments.contains("--disable-login") {
    let on = CommandLine.arguments.contains("--enable-login")
    let ok = LoginItem.setEnabled(on)
    print("login item \(on ? "enabled" : "disabled"): \(ok ? "ok" : "FAILED") (status \(LoginItem.status.rawValue))")
    exit(ok ? 0 : 1)
}

guard let backlight = Backlight() else {
    print("No controllable keyboard backlight (needs an Apple Silicon MacBook).")
    exit(1)
}

if CommandLine.arguments.contains("--duty") {
    print(backlight.duty.map { "\($0)" } ?? "off", "brightness", backlight.brightness)
    exit(0)
}

let bundleID = Bundle.main.bundleIdentifier ?? "dev.isaacharper.lowlight"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains(where: { $0.processIdentifier != getpid() }) {
    exit(0)
}

let dimmer = Dimmer(backlight: backlight)
let app = NSApplication.shared
let delegate = AppDelegate(dimmer: dimmer)
app.delegate = delegate
app.setActivationPolicy(.accessory)

signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler { NSApp.terminate(nil) }
sigterm.resume()

app.run()
