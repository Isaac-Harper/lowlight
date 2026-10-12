import AppKit

enum Links {
    static let repo = URL(string: "https://github.com/Isaac-Harper/lowlight")!
    static let newIssue = URL(string: "https://github.com/Isaac-Harper/lowlight/issues/new/choose")!
    static let latestRelease = URL(string: "https://api.github.com/repos/Isaac-Harper/lowlight/releases/latest")!
}

final class Updater {
    struct Release {
        let version: String
        let url: URL
    }

    private struct Latest: Decodable {
        let tagName: String
        let htmlUrl: URL
    }

    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    var onUpdate: ((Release) -> Void)?
    private var timer: Timer?
    private var checking = false
    private var pendingManual = false

    func start() {
        guard Self.currentVersion != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.check(manual: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.check(manual: false)
        }
    }

    func check(manual: Bool) {
        guard let current = Self.currentVersion else { return }
        guard !checking else {
            if manual { pendingManual = true }
            return
        }
        checking = true
        var request = URLRequest(url: Links.latestRelease, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Lowlight/\(current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            var latest: Latest?
            if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                latest = try? decoder.decode(Latest.self, from: data)
            }
            let offline = error is URLError
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let manual = manual || pendingManual
                checking = false
                pendingManual = false
                finish(latest, current: current, manual: manual, offline: offline)
            }
        }.resume()
    }

    private func finish(_ latest: Latest?, current: String, manual: Bool, offline: Bool) {
        guard let latest else {
            if manual {
                alert("Couldn't Check for Updates", offline
                    ? "Check your internet connection and try again."
                    : "GitHub couldn't be reached right now. Try again later.")
            }
            return
        }
        let version = latest.tagName.hasPrefix("v") ? String(latest.tagName.dropFirst()) : latest.tagName
        guard Self.isNewer(version, than: current) else {
            if manual { alert("You're up to date", "Lowlight \(current) is the latest version.") }
            return
        }
        let release = Release(version: version, url: latest.htmlUrl)
        onUpdate?(release)
        if manual {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Lowlight \(version) is available"
            alert.informativeText = "You have \(current). Download the new version from GitHub."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.url)
            }
        }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = components(a), y = components(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
