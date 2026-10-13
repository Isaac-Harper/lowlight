import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let dimmer: Dimmer
    private var statusItem: NSStatusItem!
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let valueLabel = NSTextField(labelWithString: "")
    private var loginItem: NSMenuItem!
    private var levelItems: [NSMenuItem] = []
    private let levels = NSMenu()
    private var stepItems: [NSMenuItem] = []
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
        buildLevels()
        menu.addItem(withTitle: "Set Level", action: nil, keyEquivalent: "").submenu = levels
        let steps = NSMenu()
        for n in Dimmer.stepChoices {
            let item = addItem(to: steps, "\(n)", #selector(pickSteps))
            item.tag = n
            stepItems.append(item)
        }
        menu.addItem(withTitle: "Steps Below Minimum", action: nil, keyEquivalent: "").submenu = steps
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
        LoginItem.migrateLegacyAgent()

        dimmer.onUserTakeover = { [weak self] setting in
            UserDefaults.standard.set(setting.position, forKey: "position")
            self?.show(setting)
        }

        let saved = UserDefaults.standard.object(forKey: "position") as? Double
        if let saved, case .sub = Setting(position: saved) {
            dimmer.apply(Setting(position: saved))
        }
        show(currentSetting)

        updater.onUpdate = { [weak self] release in
            self?.releaseURL = release.url
            self?.updateItem.title = "Update Available: \(release.version)"
            self?.updateItem.isHidden = false
        }
        updater.start()

        let defaults = UserDefaults.standard
        if saved != nil { defaults.set(true, forKey: "didOnboard") }
        if !defaults.bool(forKey: "didOnboard") ||
            (isInstalled && defaults.bool(forKey: "needsLoginOffer") && !LoginItem.isEnabled) {
            DispatchQueue.main.async { self.onboard() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMenu()
        return false
    }

    private func onboard() {
        UserDefaults.standard.set(true, forKey: "didOnboard")
        UserDefaults.standard.set(!isInstalled, forKey: "needsLoginOffer")
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Lowlight is in your menu bar"
        alert.informativeText = "Click the moon icon in the menu bar to dim the keyboard backlight below the macOS minimum. If you can't see it, open Lowlight again to show the menu."
        if isInstalled {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Open at Login"
            alert.suppressionButton?.state = .on
        } else {
            alert.informativeText += " To open it at login, move Lowlight to Applications first."
        }
        alert.runModal()
        let login = alert.suppressionButton?.state == .on
        if isInstalled && login != LoginItem.isEnabled { setLogin(login) }
        DispatchQueue.main.async { self.showMenu() }
    }

    private var isInstalled: Bool {
        let path = Bundle.main.bundlePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return !path.contains("/AppTranslocation/") &&
            (path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/"))
    }

    private var statusItemOnScreen: Bool {
        guard let window = statusItem.button?.window, window.occlusionState.contains(.visible),
              let screen = window.screen else { return false }
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return true }
        let x = window.frame.midX
        return x < left.maxX || x > right.minX
    }

    private func showMenu() {
        if statusItemOnScreen {
            statusItem.button?.performClick(nil)
            return
        }
        NSApp.activate()
        statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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
        LoginItem.removeLegacyAgent()
    }

    func menuWillOpen(_ menu: NSMenu) {
        show(currentSetting)
        loginItem.state = LoginItem.isEnabled ? .on : .off
        stepItems.forEach { $0.state = $0.tag == Dimmer.subSteps ? .on : .off }
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
        valueLabel.frame = NSRect(x: 136, y: 34, width: 110, height: 18)
        slider.frame = NSRect(x: 14, y: 6, width: 232, height: 24)
        slider.setAccessibilityLabel("Keyboard Backlight")
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)
        [title, valueLabel, slider].forEach(view.addSubview)
        return view
    }

    private func show(_ setting: Setting) {
        slider.doubleValue = setting.position
        valueLabel.stringValue = setting.label
        slider.setAccessibilityValueDescription(setting.spokenLabel)
        markLevel(setting)
    }

    private func buildLevels() {
        levels.removeAllItems()
        levelItems = ([Setting.off] + (1...Dimmer.subSteps).map(Setting.sub)).map { setting in
            let item = addItem(to: levels, setting.menuTitle, #selector(pickLevel))
            item.representedObject = setting.position
            return item
        }
    }

    private func markLevel(_ setting: Setting) {
        levelItems.forEach { $0.state = $0.representedObject as? Double == setting.position ? .on : .off }
    }

    @objc private func sliderMoved() {
        let setting = Setting(position: slider.doubleValue)
        valueLabel.stringValue = setting.label
        slider.setAccessibilityValueDescription(setting.spokenLabel)
        markLevel(setting)
        guard setting != currentSetting else { return }
        dimmer.apply(setting)
        UserDefaults.standard.set(setting.position, forKey: "position")
    }

    @objc private func pickLevel(_ sender: NSMenuItem) {
        guard let position = sender.representedObject as? Double else { return }
        let setting = Setting(position: position)
        dimmer.apply(setting)
        UserDefaults.standard.set(position, forKey: "position")
        show(setting)
    }

    @objc private func pickSteps(_ sender: NSMenuItem) {
        guard sender.tag != Dimmer.subSteps else { return }
        let position = currentSetting.position
        Dimmer.subSteps = sender.tag
        buildLevels()
        let setting = Setting(position: position)
        if case .sub = setting {
            dimmer.apply(setting)
            UserDefaults.standard.set(setting.position, forKey: "position")
        }
        show(currentSetting)
    }

    @objc private func toggleLogin() {
        setLogin(!LoginItem.isEnabled)
    }

    private func setLogin(_ enabled: Bool) {
        guard !LoginItem.setEnabled(enabled) else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Couldn't Turn \(enabled ? "On" : "Off") Open at Login"
        alert.informativeText = "\(enabled ? "Add" : "Remove") Lowlight in System Settings > General > Login Items & Extensions."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
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
