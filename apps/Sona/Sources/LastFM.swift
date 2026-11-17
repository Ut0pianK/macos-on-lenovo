import Foundation
import CryptoKit
import AppKit
import Security

@MainActor
final class LastFM: ObservableObject {
    struct Pending: Codable { var artist: String; var track: String; var album: String; var duration: Int; var timestamp: Int }

    @Published var apiKey: String = UserDefaults.standard.string(forKey: "lfm.key") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "lfm.key") }
    }
    @Published var apiSecret: String = Keychain.get("lfm.secret") ?? "" {
        didSet { Keychain.set("lfm.secret", apiSecret) }
    }
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "lfm.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "lfm.enabled") }
    }
    @Published private(set) var username: String? = UserDefaults.standard.string(forKey: "lfm.user")
    @Published private(set) var status: String = ""
    @Published private(set) var pendingCount = 0

    private var sessionKey: String? = Keychain.get("lfm.session")
    private var authToken: String?
    private var pending: [Pending] = []
    private let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    var connected: Bool { sessionKey != nil && !apiKey.isEmpty && !apiSecret.isEmpty }

    private var pendingURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sona/scrobbles.json")
    }

    init() {
        if let d = try? Data(contentsOf: pendingURL), let p = try? JSONDecoder().decode([Pending].self, from: d) { pending = p }
        pendingCount = pending.count
    }

    func beginAuth() async {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else { status = "API 키와 비밀을 먼저 넣어 주세요"; return }
        do {
            let r = try await call(["method": "auth.getToken"], signed: true, post: false)
            guard let token = r["token"] as? String else { status = "토큰을 받지 못했어요"; return }
            authToken = token
            NSWorkspace.shared.open(URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)")!)
            status = "브라우저에서 허락한 뒤 '연결 마치기'를 누르세요"
        } catch { status = "실패: \(error.localizedDescription)" }
    }

    func finishAuth() async {
        guard let token = authToken else { status = "먼저 '연결 시작'을 누르세요"; return }
        do {
            let r = try await call(["method": "auth.getSession", "token": token], signed: true, post: false)
            guard let s = r["session"] as? [String: Any], let key = s["key"] as? String else { status = "세션을 받지 못했어요"; return }
            sessionKey = key; Keychain.set("lfm.session", key)
            username = s["name"] as? String; UserDefaults.standard.set(username, forKey: "lfm.user")
            authToken = nil
            status = "연결됨"
            await flush()
        } catch { status = "실패: \(error.localizedDescription)" }
    }

    func disconnect() {
        sessionKey = nil; Keychain.set("lfm.session", nil)
        username = nil; UserDefaults.standard.removeObject(forKey: "lfm.user")
        status = "연결 해제됨"
    }

    func nowPlaying(_ t: Track) {
        guard enabled, connected, !t.artist.isEmpty else { return }
        var p = ["method": "track.updateNowPlaying", "artist": t.artist, "track": t.title, "duration": String(Int(t.duration))]
        if !t.album.isEmpty { p["album"] = t.album }
        Task { _ = try? await call(p, signed: true, post: true) }
    }

    func scrobble(_ t: Track, startedAt: Date) {
        guard enabled, !apiKey.isEmpty, !t.artist.isEmpty, t.duration > 30 else { return }
        pending.append(Pending(artist: t.artist, track: t.title, album: t.album, duration: Int(t.duration),
                               timestamp: Int(startedAt.timeIntervalSince1970)))
        savePending()
        Task { await flush() }
    }

    func flush() async {
        guard connected, !pending.isEmpty else { return }
        while !pending.isEmpty {
            let batch = Array(pending.prefix(50))
            var p = ["method": "track.scrobble"]
            for (i, s) in batch.enumerated() {
                p["artist[\(i)]"] = s.artist; p["track[\(i)]"] = s.track
                p["timestamp[\(i)]"] = String(s.timestamp); p["duration[\(i)]"] = String(s.duration)
                if !s.album.isEmpty { p["album[\(i)]"] = s.album }
            }
            do {
                _ = try await call(p, signed: true, post: true)
                pending.removeFirst(batch.count); savePending()
                status = "스크로블 보냄"
            } catch {
                status = "스크로블 대기 중 (\(pending.count)개): \(error.localizedDescription)"
                return
            }
        }
    }

    private func savePending() {
        pendingCount = pending.count
        if let d = try? JSONEncoder().encode(pending) { try? d.write(to: pendingURL, options: .atomic) }
    }

    private func call(_ params: [String: String], signed: Bool, post: Bool) async throws -> [String: Any] {
        var p = params
        p["api_key"] = apiKey
        if let sk = sessionKey, p["method"] != "auth.getToken", p["method"] != "auth.getSession" { p["sk"] = sk }
        if signed {
            let base = p.keys.sorted().map { $0 + p[$0]! }.joined() + apiSecret
            p["api_sig"] = Insecure.MD5.hash(data: Data(base.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        p["format"] = "json"
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let body = p.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&")
        var req: URLRequest
        if post {
            req = URLRequest(url: endpoint); req.httpMethod = "POST"; req.httpBody = Data(body.utf8)
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else {
            req = URLRequest(url: URL(string: endpoint.absoluteString + "?" + body)!)
        }
        req.setValue("Sona/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LFMError("응답을 읽을 수 없음") }
        if let code = obj["error"] as? Int {
            if code == 9 { disconnect() }
            throw LFMError((obj["message"] as? String) ?? "오류 \(code)")
        }
        return obj
    }
}

struct LFMError: LocalizedError { let msg: String; init(_ m: String) { msg = m }; var errorDescription: String? { msg } }

enum Keychain {
    private static let service = "local.sona.player"
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ key: String, _ value: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = q; add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
