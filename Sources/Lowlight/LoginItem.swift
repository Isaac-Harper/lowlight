import ServiceManagement

enum LoginItem {
    private static let app = SMAppService.mainApp
    private static let legacyAgent = SMAppService.agent(plistName: "dev.isaacharper.lowlight.plist")
    private static let runningAsLegacyAgent =
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == "dev.isaacharper.lowlight"

    static var status: SMAppService.Status { app.status }

    static var isEnabled: Bool { status == .enabled }

    static var hasLegacyAgent: Bool { legacyAgent.status == .enabled }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try app.register()
                if app.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try app.unregister()
            }
            return true
        } catch {
            NSLog("login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return false
        }
    }

    static func migrateLegacyAgent() {
        guard hasLegacyAgent else { return }
        if !isEnabled { try? app.register() }
        if !runningAsLegacyAgent { removeLegacyAgent() }
    }

    // Unregistering the agent stops its job, so the agent's own process does this only on the way out.
    static func removeLegacyAgent() {
        guard hasLegacyAgent else { return }
        do {
            try legacyAgent.unregister()
        } catch {
            NSLog("legacy login agent unregister failed: \(error.localizedDescription)")
        }
    }
}
