
import AppKit

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/usage")
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func json(_ name: String) -> [String: Any]? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    func claudeRunning() -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-x", "claude"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }

    func window(_ rl: [String: Any]?, _ key: String) -> (pct: Int, reset: Date)? {
        guard let w = rl?[key] as? [String: Any], let p = w["used_percentage"] as? Double, let r = w["resets_at"] as? Double else { return nil }
        let reset = Date(timeIntervalSince1970: r)
        return reset > Date() ? (Int(p), reset) : nil
    }

    func refresh() {
        item.isVisible = claudeRunning()
        guard item.isVisible else { return }
        let lim = json("limits.json"); let rl = lim?["rate_limits"] as? [String: Any]
        let h = window(rl, "five_hour"), w = window(rl, "seven_day")
        let tf = DateFormatter(); tf.dateFormat = "M/d HH:mm"
        let title = "✳︎ " + (h.map { "\($0.pct)%" } ?? "–") + " · " + (w.map { "\($0.pct)%" } ?? "–")
        item.button?.title = title
        let top = max(h?.pct ?? 0, w?.pct ?? 0)
        item.button?.contentTintColor = top >= 90 ? .systemRed : top >= 70 ? .systemOrange : nil

        let menu = NSMenu()
        func add(_ s: String) { let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }
        add("5시간(세션): " + (h.map { "\($0.pct)% 사용 · \(tf.string(from: $0.reset)) 초기화" } ?? "정보 없음"))
        add("주간: " + (w.map { "\($0.pct)% 사용 · \(tf.string(from: $0.reset)) 초기화" } ?? "정보 없음"))
        menu.addItem(.separator())
        if let at = lim?["at"] as? Double { add("마지막 갱신: " + tf.string(from: Date(timeIntervalSince1970: at)) + ((lim?["model"] as? String).map { " · \($0)" } ?? "")) }
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
