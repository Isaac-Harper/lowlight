import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let dimmer: Dimmer
    private var statusItem: NSStatusItem!
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let valueLabel = NSTextField(labelWithString: "")
    private var loginItem: NSMenuItem!

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
        loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        let quit = NSMenuItem(title: "Quit Lowlight", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        dimmer.onUserTakeover = { [weak self] setting in
            UserDefaults.standard.set(setting.position, forKey: "position")
            self?.show(setting)
        }

        let saved = UserDefaults.standard.object(forKey: "position") as? Double
        if let saved, case .sub = Setting(position: saved) {
            dimmer.apply(Setting(position: saved))
        }
        show(currentSetting)
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        guard setting != dimmer.setting else { return }
        dimmer.apply(setting)
        UserDefaults.standard.set(setting.position, forKey: "position")
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
