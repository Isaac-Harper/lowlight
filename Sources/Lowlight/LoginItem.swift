import ServiceManagement

enum LoginItem {
    private static let agent = SMAppService.agent(plistName: "dev.isaacharper.lowlight.plist")

    static var status: SMAppService.Status { agent.status }

    static var isEnabled: Bool { status == .enabled }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try agent.register()
                if agent.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try agent.unregister()
            }
            return true
        } catch {
            NSLog("login agent \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return false
        }
    }
}
