
import SwiftUI
import AppKit

let listPath = "/usr/local/etc/mx450/allow-apps.txt"

struct Entry: Identifiable, Hashable { let id = UUID(); var app: String; var names: [String] }

@MainActor final class Model: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var allowAll = false
    @Published var powered = false
    @Published var holders: [String] = []
    @Published var onAC = false
    @Published var error: String?
    private var timer: Timer?

    init() { load(); refresh(); timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } } }

    func load() {
        entries = []; allowAll = false
        guard let text = try? String(contentsOfFile: listPath, encoding: .utf8) else { error = "목록 파일을 읽을 수 없음: \(listPath)"; return }
        var cur: Entry?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") { if let c = cur { entries.append(c) }; cur = Entry(app: String(line.dropFirst(3)), names: []) }
            else if line == "*" { allowAll = true }
            else if line.isEmpty || line.hasPrefix("#") { continue }
            else if cur != nil { cur!.names.append(line) }
            else { cur = Entry(app: line, names: [line]) }
        }
        if let c = cur { entries.append(c) }
    }

    func save() {
        var out = ["# MX450(외장 그래픽)을 써도 되는 앱의 실행 파일 이름 — 한 줄에 하나. \"MX450 앱 관리\" 앱으로 고치세요.",
                   "# 충전기를 꽂았을 때만 적용됩니다(배터리에서는 어떤 앱도 MX450 을 받지 않음). 새로 실행하는 앱부터 적용.",
                   "# \"*\" 한 줄을 넣으면 예전처럼 모든 앱에 허용합니다."]
        if allowAll { out.append("*") }
        for e in entries { out.append("## \(e.app)"); out.append(contentsOf: e.names) }
        do { try (out.joined(separator: "\n") + "\n").write(toFile: listPath, atomically: false, encoding: .utf8); error = nil }
        catch { self.error = "저장 실패: \(error.localizedDescription)" }
    }

    func add(_ url: URL) {
        guard let b = Bundle(url: url), let exe = b.infoDictionary?["CFBundleExecutable"] as? String else { error = "앱의 실행 파일 이름을 읽을 수 없음"; return }
        var names = [exe]

        if let en = FileManager.default.enumerator(at: url.appendingPathComponent("Contents"), includingPropertiesForKeys: nil) {
            for case let u as URL in en where u.pathExtension == "app" {
                if let hb = Bundle(url: u), let h = hb.infoDictionary?["CFBundleExecutable"] as? String, !names.contains(h) { names.append(h) }
                en.skipDescendants()
            }
        }
        let name = (b.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        entries.removeAll { $0.app == name }
        entries.append(Entry(app: name, names: names)); save()
    }

    func remove(_ e: Entry) { entries.removeAll { $0.id == e.id }; save() }

    func sh(_ cmd: String) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", cmd]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }

    func refresh() {
        let acc = sh("/usr/sbin/ioreg -r -c NVAccel -w0 -l | /usr/bin/grep -o -E '\"vramUsedBytes\"|\"IOUserClientCreator\" = \"[^\"]*\"'")
        powered = acc.contains("vramUsedBytes")
        var seen: [String] = []
        for line in acc.split(separator: "\n") where line.contains("IOUserClientCreator") {
            if let r = line.range(of: ", "), let end = line.lastIndex(of: "\"") { let n = String(line[r.upperBound..<end]); if !seen.contains(n) { seen.append(n) } }
        }
        holders = seen
        onAC = sh("/usr/bin/pmset -g batt | /usr/bin/head -1").contains("AC Power")
    }
}

struct ContentView: View {
    @StateObject var m = Model()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(m.powered ? Color.green : Color.secondary).frame(width: 10, height: 10)
                Text(m.powered ? "MX450 켜짐" : "MX450 꺼짐 (절전)").font(.headline)
                Spacer()
                Text(m.onAC ? "충전기 연결됨" : "배터리 사용 중 — 어떤 앱도 MX450 을 받지 않음").font(.callout).foregroundStyle(.secondary)
            }
            if !m.holders.isEmpty {
                Text("지금 MX450 을 잡고 있는 앱: " + m.holders.joined(separator: ", ")).font(.callout)
                Text("이 앱들을 닫아야 MX450 이 꺼집니다. 충전기를 뽑아도 열려 있는 동안은 계속 켜져 있어요.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("MX450 을 써도 되는 앱").font(.headline)
                Spacer()
                Button("앱 추가…") {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.application]; p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowsMultipleSelection = true
                    if p.runModal() == .OK { for u in p.urls { m.add(u) } }
                }
            }
            if m.entries.isEmpty {
                Text("목록이 비어 있어요. 지금은 어떤 앱도 MX450 을 쓰지 않습니다.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                List {
                    ForEach(m.entries) { e in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.app)
                                Text(e.names.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button("빼기") { m.remove(e) }
                        }
                    }
                }.frame(minHeight: 140)
            }
            Toggle("모든 앱에 허용 (권하지 않음: 상주 앱이 MX450 을 붙잡아 배터리가 빨리 닳아요)", isOn: Binding(get: { m.allowAll }, set: { m.allowAll = $0; m.save() }))
            Text("충전기를 꽂았을 때만 적용되고, 바꾼 뒤 새로 실행하는 앱부터 반영됩니다(몇 초 걸림). \"Helium (MX450)\" 은 목록과 상관없이 MX450 을 씁니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let e = m.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .padding(16).frame(minWidth: 520, minHeight: 380)
    }
}

@main struct MX450App: App {
    var body: some Scene { WindowGroup("MX450 앱 관리") { ContentView() }.windowResizability(.contentSize) }
}
