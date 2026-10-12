import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let dimmer: Dimmer
    private var statusItem: NSStatusItem!
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let valueLabel = NSTextField(labelWithString: "")
    private var loginItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private let updater = Updater()
    private var releaseURL: URL?

    init(dimmer: Dimmer) {
        self.dimmer = dimmer
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: "Lowlight")

        let menu = NSMenu()
        menu.delegate = self
        let sliderItem = NSMenuItem()
        sliderItem.view = makeSliderView()
        menu.addItem(sliderItem)
        menu.addItem(.separator())
        updateItem = addItem(to: menu, "", #selector(openRelease))
        updateItem.isHidden = true
        loginItem = addItem(to: menu, "Open at Login", #selector(toggleLogin))
        if Updater.currentVersion != nil {
            addItem(to: menu, "Check for Updates\u{2026}", #selector(checkForUpdates))
        }
        addItem(to: menu, "Report an Issue\u{2026}", #selector(reportIssue))
        menu.addItem(.separator())
        if let version = Updater.currentVersion {
            let versionItem = NSMenuItem(title: "Lowlight \(version)", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            menu.addItem(versionItem)
        }
        addItem(to: menu, "Quit Lowlight", #selector(quit), key: "q")
        statusItem.menu = menu

        dimmer.onUserTakeover = { [weak self] setting in
            UserDefaults.standard.set(setting.position, forKey: "position")
            self?.show(setting)
        }

        let saved = UserDefaults.standard.object(forKey: "position") as? Double
        if let saved {
            dimmer.apply(Setting(position: saved))
        }
        show(currentSetting)

        updater.onUpdate = { [weak self] release in
            self?.releaseURL = release.url
            self?.updateItem.title = "Update Available: \(release.version)"
            self?.updateItem.isHidden = false
        }
        updater.start()

        if saved != nil { UserDefaults.standard.set(true, forKey: "didOnboard") }
        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            DispatchQueue.main.async { self.onboard() }
        }
    }

    private func onboard() {
        UserDefaults.standard.set(true, forKey: "didOnboard")
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Lowlight is in your menu bar"
        alert.informativeText = "Click the moon icon in the menu bar to dim the keyboard backlight below the macOS minimum."
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Open at Login"
        alert.suppressionButton?.state = .on
        alert.runModal()
        LoginItem.setEnabled(alert.suppressionButton?.state == .on)
        DispatchQueue.main.async { self.statusItem.button?.performClick(nil) }
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(currentSetting.position, forKey: "position")
        dimmer.releaseToFloor()
    }

    func menuWillOpen(_ menu: NSMenu) {
        show(currentSetting)
        loginItem.state = LoginItem.isEnabled ? .on : .off
    }

    private var currentSetting: Setting {
        if case .sub = dimmer.setting { return dimmer.setting }
        return dimmer.systemSetting
    }

    private func makeSliderView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))
        let title = NSTextField(labelWithString: "Keyboard Backlight")
        title.font = .menuFont(ofSize: 0)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: 14, y: 34, width: 140, height: 18)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 100, y: 34, width: 146, height: 18)
        slider.frame = NSRect(x: 14, y: 6, width: 232, height: 24)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)
        [title, valueLabel, slider].forEach(view.addSubview)
        return view
    }

    private func show(_ setting: Setting) {
        slider.doubleValue = setting.position
        valueLabel.stringValue = setting.label
    }

    @objc private func sliderMoved() {
        let setting = Setting(position: slider.doubleValue)
        valueLabel.stringValue = setting.label
        guard setting != currentSetting else { return }
        dimmer.apply(setting)
        UserDefaults.standard.set(setting.position, forKey: "position")
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func openRelease() {
        if let releaseURL { NSWorkspace.shared.open(releaseURL) }
    }

    @objc private func checkForUpdates() {
        updater.check(manual: true)
    }

    @objc private func reportIssue() {
        NSWorkspace.shared.open(Links.newIssue)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
