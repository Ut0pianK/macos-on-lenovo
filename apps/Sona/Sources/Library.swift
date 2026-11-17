import Foundation
import AVFoundation
import AppKit
import CoreServices

struct Track: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var genre: String
    var year: Int
    var trackNumber: Int
    var duration: Double
    var fileSize: Int64
    var modified: Double
    var dateAdded: Date
    var playCount: Int = 0
    var lastPlayed: Date? = nil
    var loved: Bool = false
    var loudness: Double? = nil
    var peak: Double? = nil

    var url: URL { URL(fileURLWithPath: id) }
    var artistSort: String { artist.isEmpty ? "알 수 없는 아티스트" : artist }
    var albumSort: String { album.isEmpty ? "알 수 없는 앨범" : album }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var trackIDs: [String]
}

private struct LibraryFile: Codable {
    var version = 1
    var tracks: [Track]
    var playlists: [Playlist]
}

@MainActor
final class LibraryStore: ObservableObject {
    nonisolated static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aif", "aiff", "caf", "flac", "alac", "m4b"]

    @Published private(set) var tracks: [Track] = []
    @Published var playlists: [Playlist] = []
    @Published private(set) var scanning = false
    @Published private(set) var scanProgress: (done: Int, total: Int) = (0, 0)
    @Published var folders: [String] {
        didSet { UserDefaults.standard.set(folders, forKey: "folders"); restartWatcher(); Task { await scan() } }
    }

    private var byID: [String: Int] = [:]
    private var busy = false
    private var lastScan = Date.distantPast
    private var saveTask: Task<Void, Never>?
    private var watcher: FolderWatcher?
    private var artworkCache = NSCache<NSString, NSImage>()
    private var missingArtwork = Set<String>()

    static let iCloudMusic = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/Music"

    private var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sona", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: "folders") {
            folders = saved
        } else {
            folders = FileManager.default.fileExists(atPath: Self.iCloudMusic) ? [Self.iCloudMusic] : []
        }
        artworkCache.countLimit = 400
        load()
        restartWatcher()
        Task { await scan() }
    }

    func track(_ id: String) -> Track? { byID[id].map { tracks[$0] } }

    func replace(_ t: Track) { if let i = byID[t.id] { tracks[i] = t } }

    func forgetArtwork(_ id: String) { artworkCache.removeObject(forKey: id as NSString); missingArtwork.remove(id) }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let file = try? JSONDecoder().decode(LibraryFile.self, from: data) else { return }
        setTracks(file.tracks)
        playlists = file.playlists
    }

    func scheduleSave() {
        saveTask?.cancel()
        let snapshot = LibraryFile(tracks: tracks, playlists: playlists)
        let url = storeURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func setTracks(_ list: [Track]) {
        tracks = list
        byID = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($1.id, $0) })
    }

    func scan() async {
        if busy { return }
        busy = true
        defer { busy = false; if scanning { scanning = false } }
        let folders = self.folders
        let existing = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })

        let files: [(String, Int64, Double)] = await Task.detached(priority: .userInitiated) {
            var out: [(String, Int64, Double)] = []
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            for folder in folders {
                guard let en = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys,
                                                               options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                while let url = en.nextObject() as? URL {
                    guard LibraryStore.audioExtensions.contains(url.pathExtension.lowercased()),
                          let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                    out.append((url.path, Int64(v.fileSize ?? 0), v.contentModificationDate?.timeIntervalSince1970 ?? 0))
                }
            }
            return out
        }.value

        var result: [Track] = []
        var toRead: [(String, Int64, Double)] = []
        for f in files {
            if let t = existing[f.0], t.modified == f.2, t.fileSize == f.1 { result.append(t) } else { toRead.append(f) }
        }
        if !toRead.isEmpty { scanning = true; scanProgress = (0, toRead.count) }
        if !toRead.isEmpty {
            var done = 0
            await withTaskGroup(of: Track?.self) { group in
                var next = 0
                func take() -> (String, Int64, Double)? { defer { next += 1 }; return next < toRead.count ? toRead[next] : nil }
                for _ in 0..<6 { if let f = take() { group.addTask { await Self.readTags(path: f.0, size: f.1, modified: f.2) } } }
                while let t = await group.next() {
                    if var t {
                        if let old = existing[t.id] { t.playCount = old.playCount; t.lastPlayed = old.lastPlayed; t.loved = old.loved; t.dateAdded = old.dateAdded
                            if old.fileSize == t.fileSize { t.loudness = old.loudness; t.peak = old.peak } }
                        result.append(t)
                    }
                    done += 1
                    if done % 20 == 0 { scanProgress = (done, toRead.count) }
                    if let f = take() { group.addTask { await Self.readTags(path: f.0, size: f.1, modified: f.2) } }
                }
            }
            scanProgress = (toRead.count, toRead.count)
        }
        result.sort { ($0.artistSort, $0.albumSort, $0.trackNumber, $0.title) < ($1.artistSort, $1.albumSort, $1.trackNumber, $1.title) }
        if result != tracks { setTracks(result); scheduleSave() }
        if UserDefaults.standard.bool(forKey: "normalize") { analyzeLoudness() }
    }

    nonisolated static func readTags(path: String, size: Int64, modified: Double) async -> Track? {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        var title = "", artist = "", album = "", genre = ""
        var year = 0, number = 0
        var duration = 0.0
        if let d = try? await asset.load(.duration) { duration = d.seconds.isFinite ? d.seconds : 0 }
        if let items = try? await asset.load(.metadata) {
            for item in items {
                let key = item.commonKey?.rawValue ?? (item.identifier?.rawValue ?? "")
                switch key {
                case "title": title = (try? await item.load(.stringValue)) ?? title
                case "artist": artist = (try? await item.load(.stringValue)) ?? artist
                case "albumName": album = (try? await item.load(.stringValue)) ?? album
                case "type": genre = (try? await item.load(.stringValue)) ?? genre
                case "creationDate": if let s = try? await item.load(.stringValue), let y = Int(s.prefix(4)) { year = y }
                default:
                    if let id = item.identifier?.rawValue {
                        if id.hasSuffix("trkn") || id.hasSuffix("TRCK") {
                            if let s = try? await item.load(.stringValue) { number = Int(s.split(separator: "/").first ?? "") ?? number }
                            else if let d = try? await item.load(.dataValue), d.count >= 4 { number = Int(d[3]) }
                        } else if id.hasSuffix("gnre") || id.hasSuffix("TCON"), genre.isEmpty {
                            genre = (try? await item.load(.stringValue)) ?? genre
                        } else if (id.hasSuffix("day") || id.hasSuffix("TDRC") || id.hasSuffix("TYER")), year == 0,
                                  let s = try? await item.load(.stringValue), let y = Int(s.prefix(4)) { year = y }
                    }
                }
            }
        }

        let base = url.deletingPathExtension().lastPathComponent
        if title.isEmpty || artist.isEmpty {
            let parts = base.components(separatedBy: " - ")
            if parts.count >= 2 {
                if artist.isEmpty { artist = parts[0].trimmingCharacters(in: .whitespaces) }
                if title.isEmpty { title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces) }
            } else if title.isEmpty { title = base }
        }
        return Track(id: path, title: title, artist: artist, album: album, genre: genre, year: year, trackNumber: number,
                     duration: duration, fileSize: size, modified: modified, dateAdded: Date())
    }

    @Published private(set) var analyzing: (done: Int, total: Int)? = nil
    private var analysisTask: Task<Void, Never>?

    func analyzeLoudness(first priority: String? = nil) {
        if let priority, let i = byID[priority], tracks[i].loudness == nil {
            let url = tracks[i].url
            Task.detached(priority: .userInitiated) {
                if let r = LoudnessMeter.measure(url: url) { await self.setLoudness(priority, r) }
            }
        }
        guard analysisTask == nil else { return }
        analysisTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let todo = self.tracks.filter { $0.loudness == nil }
                guard let next = todo.first else { break }
                self.analyzing = (self.tracks.count - todo.count, self.tracks.count)
                let url = next.url, id = next.id
                let r = await Task.detached(priority: .background) { LoudnessMeter.measure(url: url) }.value
                self.setLoudness(id, r ?? LoudnessMeter.Result(lufs: -16, peak: 1))
            }
            self?.analyzing = nil
            self?.analysisTask = nil
        }
    }

    private func setLoudness(_ id: String, _ r: LoudnessMeter.Result) {
        guard let i = byID[id] else { return }
        tracks[i].loudness = r.lufs; tracks[i].peak = r.peak
        scheduleSave()
        NotificationCenter.default.post(name: .sonaLoudnessUpdated, object: id)
    }

    func markPlayed(_ id: String) {
        guard let i = byID[id] else { return }
        tracks[i].playCount += 1
        tracks[i].lastPlayed = Date()
        scheduleSave()
    }

    func toggleLoved(_ id: String) {
        guard let i = byID[id] else { return }
        tracks[i].loved.toggle()
        scheduleSave()
    }

    func newPlaylist(named name: String, with ids: [String] = []) -> Playlist {
        let p = Playlist(name: name, trackIDs: ids)
        playlists.append(p); scheduleSave(); return p
    }
    func add(_ ids: [String], to playlist: Playlist.ID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist }) else { return }
        playlists[i].trackIDs.append(contentsOf: ids.filter { !playlists[i].trackIDs.contains($0) })
        scheduleSave()
    }
    func remove(_ ids: Set<String>, from playlist: Playlist.ID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist }) else { return }
        playlists[i].trackIDs.removeAll { ids.contains($0) }
        scheduleSave()
    }
    func rename(_ playlist: Playlist.ID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist }) else { return }
        playlists[i].name = name; scheduleSave()
    }
    func delete(_ playlist: Playlist.ID) {
        playlists.removeAll { $0.id == playlist }; scheduleSave()
    }

    func artwork(for id: String) async -> NSImage? {
        if let img = artworkCache.object(forKey: id as NSString) { return img }
        if missingArtwork.contains(id) { return nil }
        let img: NSImage? = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: URL(fileURLWithPath: id))
            guard let items = try? await asset.load(.commonMetadata) else { return nil }
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork) {
                if let d = try? await item.load(.dataValue), let img = NSImage(data: d) { return img }
            }
            return nil
        }.value
        if let img { artworkCache.setObject(img, forKey: id as NSString) } else { missingArtwork.insert(id) }
        return img
    }

    private func restartWatcher() {
        watcher = nil
        guard !folders.isEmpty else { return }
        watcher = FolderWatcher(paths: folders) { [weak self] in
            Task { @MainActor in guard let self, Date().timeIntervalSince(self.lastScan) > 10 else { return }; self.lastScan = Date(); await self.scan() }
        }
    }
}

final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(paths: [String], onChange: @escaping () -> Void) {
        self.onChange = onChange
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        stream = FSEventStreamCreate(nil, cb, &ctx, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }

    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}

extension Notification.Name {
    static let sonaLoudnessUpdated = Notification.Name("sonaLoudnessUpdated")
}
