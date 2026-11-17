import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct TagChanges {
    var title: String?, artist: String?, album: String?, albumArtist: String?, genre: String?
    var year: Int?, trackNumber: Int?
    var artwork: Data?
    var isEmpty: Bool { title == nil && artist == nil && album == nil && albumArtist == nil && genre == nil && year == nil && trackNumber == nil && artwork == nil }
}

enum TagWriter {

    static func write(_ c: TagChanges, to url: URL) async throws -> Bool {
        guard ["m4a", "mp4", "m4b", "aac"].contains(url.pathExtension.lowercased()) else { return false }
        let asset = AVURLAsset(url: url)
        var items = ((try? await asset.load(.metadata)) ?? []).filter { $0.keySpace == .iTunes }
        func set(_ id: AVMetadataIdentifier, _ value: (NSCopying & NSObjectProtocol)?, dataType: String? = nil) {
            items.removeAll { $0.identifier == id }
            guard let value else { return }
            let m = AVMutableMetadataItem(); m.identifier = id; m.value = value
            if let dataType { m.dataType = dataType }
            items.append(m)
        }
        func text(_ id: AVMetadataIdentifier, _ s: String?) { if let s { set(id, s.isEmpty ? nil : s as NSString) } }
        text(.iTunesMetadataSongName, c.title)
        text(.iTunesMetadataArtist, c.artist)
        text(.iTunesMetadataAlbum, c.album)
        text(.iTunesMetadataAlbumArtist, c.albumArtist)
        if let g = c.genre { items.removeAll { $0.identifier == .iTunesMetadataGenreID }; text(.iTunesMetadataUserGenre, g) }
        if let y = c.year { set(.iTunesMetadataReleaseDate, y > 0 ? String(y) as NSString : nil) }
        if let n = c.trackNumber {
            let bytes: [UInt8] = [0, 0, UInt8((n >> 8) & 0xff), UInt8(n & 0xff), 0, 0, 0, 0]
            set(.iTunesMetadataTrackNumber, n > 0 ? Data(bytes) as NSData : nil, dataType: kCMMetadataBaseDataType_RawData as String)
        }
        if let art = c.artwork {
            let png = art.starts(with: [0x89, 0x50, 0x4E, 0x47])
            set(.iTunesMetadataCoverArt, art as NSData, dataType: (png ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG) as String)
        }

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw LFMError("내보내기를 만들 수 없음")
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        export.metadata = items
        try await export.export(to: tmp, as: .m4a)

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        return true
    }
}

extension LibraryStore {

    func updateTags(_ ids: [String], _ c: TagChanges) async -> (written: Int, libraryOnly: Int, failed: [String]) {
        var written = 0, only = 0
        var failed: [String] = []
        for id in ids {
            guard var t = track(id) else { continue }
            do {
                if try await TagWriter.write(c, to: t.url) { written += 1 } else { only += 1 }
            } catch {
                failed.append("\(t.url.lastPathComponent): \(error.localizedDescription)"); continue
            }
            if let v = c.title { t.title = v }
            if let v = c.artist { t.artist = v }
            if let v = c.album { t.album = v }
            if let v = c.genre { t.genre = v }
            if let v = c.year { t.year = v }
            if let v = c.trackNumber { t.trackNumber = v }
            let attrs = try? FileManager.default.attributesOfItem(atPath: t.id)
            if let m = attrs?[.modificationDate] as? Date { t.modified = m.timeIntervalSince1970 }
            if let s = attrs?[.size] as? NSNumber { t.fileSize = s.int64Value }
            replace(t)
            if c.artwork != nil { forgetArtwork(id) }
        }
        scheduleSave()
        return (written, only, failed)
    }
}

struct TagEditor: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let ids: [String]

    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var albumArtist = ""
    @State private var genre = ""
    @State private var year = ""
    @State private var number = ""
    @State private var original: [String: String] = [:]
    @State private var artwork: Data?
    @State private var saving = false
    @State private var message: String?

    private var tracks: [Track] { ids.compactMap { library.track($0) } }
    private var multi: Bool { ids.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    if let artwork, let img = NSImage(data: artwork) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        ArtworkView(trackID: ids.first, size: 120)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in if let u = urls.first, let d = try? Data(contentsOf: u), NSImage(data: d) != nil { artwork = d; return true }; return false }
                VStack(alignment: .leading, spacing: 4) {
                    Text(multi ? "\(ids.count)곡 정보" : (tracks.first?.title ?? "")).font(.title3.bold()).lineLimit(2)
                    if !multi, let t = tracks.first {
                        Text(t.url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Text("\(formatTime(t.duration)) · \(ByteCountFormatter.string(fromByteCount: t.fileSize, countStyle: .file)) · 재생 \(t.playCount)회")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if multi { Text("비워 둔 칸은 곡마다 원래 값을 그대로 둬요").font(.caption).foregroundStyle(.secondary) }
                    Button("앨범 아트 바꾸기…") {
                        let p = NSOpenPanel(); p.allowedContentTypes = [.image]
                        if p.runModal() == .OK, let u = p.url, let d = try? Data(contentsOf: u), let img = NSImage(data: d) {
                            artwork = jpegData(img) ?? d
                        }
                    }.padding(.top, 6)
                }
            }
            Form {
                field("제목", $title, "title")
                field("아티스트", $artist, "artist")
                field("앨범", $album, "album")
                field("앨범 아티스트", $albumArtist, "albumArtist")
                field("장르", $genre, "genre")
                HStack {
                    field("연도", $year, "year")
                    field("트랙 번호", $number, "number")
                }
            }
            .formStyle(.columns)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "저장 중…" : "저장") { Task { await save() } }.keyboardShortcut(.defaultAction).disabled(saving)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: fill)
    }

    @ViewBuilder private func field(_ label: String, _ v: Binding<String>, _ key: String) -> some View {
        TextField(label, text: v, prompt: Text(multi && original[key] == nil ? "여러 값" : ""))
    }

    private func fill() {
        func common(_ f: (Track) -> String) -> String? {
            let vals = Set(tracks.map(f)); return vals.count == 1 ? vals.first : nil
        }
        let pairs: [(String, (Track) -> String)] = [
            ("title", { $0.title }), ("artist", { $0.artist }), ("album", { $0.album }), ("albumArtist", { _ in "" }),
            ("genre", { $0.genre }), ("year", { $0.year > 0 ? "\($0.year)" : "" }), ("number", { $0.trackNumber > 0 ? "\($0.trackNumber)" : "" }),
        ]
        for (k, f) in pairs { if let v = common(f) { original[k] = v } }
        if multi { original["title"] = nil }
        title = original["title"] ?? ""; artist = original["artist"] ?? ""; album = original["album"] ?? ""
        albumArtist = original["albumArtist"] ?? ""; genre = original["genre"] ?? ""; year = original["year"] ?? ""; number = original["number"] ?? ""
    }

    private func save() async {

        func changed(_ key: String, _ value: String) -> String? {
            let v = value.trimmingCharacters(in: .whitespaces)
            if let o = original[key] { return v == o ? nil : v }
            return v.isEmpty ? nil : v
        }
        var c = TagChanges()
        c.title = changed("title", title); c.artist = changed("artist", artist); c.album = changed("album", album)
        c.albumArtist = changed("albumArtist", albumArtist); c.genre = changed("genre", genre)
        if let y = changed("year", year) { c.year = Int(y) ?? 0 }
        if let n = changed("number", number) { c.trackNumber = Int(n) ?? 0 }
        c.artwork = artwork
        if c.isEmpty { dismiss(); return }
        saving = true
        let r = await library.updateTags(ids, c)
        saving = false
        if r.failed.isEmpty && r.libraryOnly == 0 { dismiss(); return }
        var lines: [String] = []
        if r.written > 0 { lines.append("파일에 저장 \(r.written)곡") }
        if r.libraryOnly > 0 { lines.append("m4a가 아니라 보관함에만 저장 \(r.libraryOnly)곡") }
        if !r.failed.isEmpty { lines.append("실패: " + r.failed.joined(separator: ", ")) }
        message = lines.joined(separator: " · ")
    }

    private func jpegData(_ img: NSImage) -> Data? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}
