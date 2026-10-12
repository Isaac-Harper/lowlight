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
    if !CommandLine.arguments.contains("--duty") {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Lowlight can't control this keyboard"
        alert.informativeText = "Lowlight needs an Apple Silicon MacBook with a built-in backlit keyboard. If this Mac has one, a macOS update may have changed the private API it uses."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Report an Issue")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(Links.newIssue)
        }
    }
    exit(0)
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
