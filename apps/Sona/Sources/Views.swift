import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case songs, artists, albums, recent, mostPlayed, loved
    case playlist(UUID)
}

func formatTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s.rounded(.down))
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}

struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var autoCollapsed = false
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var converter: Converter
    @State private var dropping = false
    @EnvironmentObject var nav: Navigator
    @State private var search = ""
    @State private var renaming: Playlist?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $nav.selection) {
                Section("보관함") {
                    Label("노래", systemImage: "music.note").tag(SidebarItem.songs)
                    Label("아티스트", systemImage: "music.mic").tag(SidebarItem.artists)
                    Label("앨범", systemImage: "square.stack").tag(SidebarItem.albums)
                }
                Section("자동 목록") {
                    Label("최근 추가", systemImage: "clock").tag(SidebarItem.recent)
                    Label("많이 들은 곡", systemImage: "chart.bar").tag(SidebarItem.mostPlayed)
                    Label("좋아하는 곡", systemImage: "heart").tag(SidebarItem.loved)
                }
                Section("플레이리스트") {
                    ForEach(library.playlists) { p in
                        Label(p.name, systemImage: "music.note.list").tag(SidebarItem.playlist(p.id))
                            .contextMenu {
                                Button("이름 바꾸기…") { renameText = p.name; renaming = p }
                                Button("삭제", role: .destructive) {
                                    if nav.selection == .playlist(p.id) { nav.selection = .songs }
                                    library.delete(p.id)
                                }
                            }
                            .dropDestination(for: String.self) { ids, _ in library.add(ids, to: p.id); return true }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        let p = library.newPlaylist(named: "새 플레이리스트")
                        nav.selection = .playlist(p.id); renameText = p.name; renaming = p
                    } label: { Label("새 플레이리스트", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    Spacer()
                    if library.scanning {
                        ProgressView().controlSize(.small)
                        if library.scanProgress.total > 0 {
                            Text("\(library.scanProgress.done)/\(library.scanProgress.total)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
            }
        } detail: {
            detail
                .searchable(text: $search, placement: .toolbar, prompt: "제목, 아티스트, 앨범 검색")
        }

        Divider()
        NowPlayingBar().padding(.horizontal, 12).padding(.vertical, 8).background(.bar)
        }
        .background(GeometryReader { g in Color.clear.onChange(of: g.size.width, initial: true) { _, w in adapt(width: w) } })
        .sheet(item: $renaming) { p in
            VStack(alignment: .leading, spacing: 12) {
                Text("플레이리스트 이름").font(.headline)
                TextField("이름", text: $renameText).frame(width: 260).onSubmit { commitRename(p) }
                HStack { Spacer(); Button("취소") { renaming = nil }; Button("저장") { commitRename(p) }.keyboardShortcut(.defaultAction) }
            }.padding(20)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            Task {
                var urls: [URL] = []
                for p in providers {
                    if let u = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data, let url = URL(dataRepresentation: u, relativeTo: nil) { urls.append(url) }
                }
                await MainActor.run { converter.enqueue(urls) }
            }
            return true
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .background(Color.accentColor.opacity(0.08))
                    .overlay(Label("놓으면 m4a로 바꿔서 보관함 폴더에 넣어요", systemImage: "square.and.arrow.down").font(.title3).padding(14).background(.regularMaterial, in: Capsule()))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) { if !converter.jobs.isEmpty { ConvertPanel().padding(.trailing, 16).padding(.bottom, 80) } }
        .overlay(alignment: .bottom) {
            if let err = player.errorMessage {
                Text(err).font(.callout).padding(8).background(.red.opacity(0.85), in: Capsule()).foregroundStyle(.white).padding()
            }
        }
    }

    private func adapt(width w: CGFloat) {
        if w < 820, columnVisibility != .detailOnly { columnVisibility = .detailOnly; autoCollapsed = true }
        else if w >= 900, autoCollapsed { columnVisibility = .all; autoCollapsed = false }
    }

    private func commitRename(_ p: Playlist) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { library.rename(p.id, to: name) }
        renaming = nil
    }

    @ViewBuilder private var detail: some View {
        switch nav.selection ?? .songs {
        case .songs: TrackTable(title: "노래", tracks: filtered(library.tracks))
        case .artists: GroupBrowser(kind: .artist, search: search)
        case .albums: GroupBrowser(kind: .album, search: search)
        case .recent:
            TrackTable(title: "최근 추가", tracks: filtered(library.tracks.sorted { $0.dateAdded > $1.dateAdded }.prefix(200).map { $0 }))
        case .mostPlayed:
            TrackTable(title: "많이 들은 곡", tracks: filtered(library.tracks.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }.prefix(100).map { $0 }))
        case .loved: TrackTable(title: "좋아하는 곡", tracks: filtered(library.tracks.filter(\.loved)), showArtwork: true)
        case .playlist(let id):
            if let p = library.playlists.first(where: { $0.id == id }) {
                TrackTable(title: p.name, tracks: filtered(p.trackIDs.compactMap { library.track($0) }), playlist: p.id)
            } else { Text("플레이리스트가 없어요").foregroundStyle(.secondary) }
        }
    }

    private func filtered(_ list: [Track]) -> [Track] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) || $0.album.localizedCaseInsensitiveContains(q) }
    }
}

struct TrackTable: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var nav: Navigator
    @State private var editing: EditRequest?
    @AppStorage("tableColumns") private var columnsData = Data()
    @State private var columns = TableColumnCustomization<Track>()
    let title: String
    let tracks: [Track]
    var playlist: Playlist.ID? = nil
    var showArtwork = false
    @State private var selection = Set<Track.ID>()
    @State private var order: [KeyPathComparator<Track>] = []

    private var sorted: [Track] { order.isEmpty ? tracks : tracks.sorted(using: order) }

    var body: some View {
        let rows = sorted
        GeometryReader { geo in
        let compact = geo.size.width < 620
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(compact ? .headline : .title2.bold()).lineLimit(1)
                    if compact { Text(summary(rows)).font(.caption).foregroundStyle(.secondary) }
                }
                if !compact { Text(summary(rows)).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 8)
                Button { player.play(rows.map(\.id)) } label: { if compact { Image(systemName: "play.fill") } else { Label("재생", systemImage: "play.fill") } }
                    .disabled(rows.isEmpty).help("재생")
                Button { player.shuffle = true; player.play(rows.map(\.id), startAt: Int.random(in: 0..<max(1, rows.count))) } label: {
                    if compact { Image(systemName: "shuffle") } else { Label("셔플", systemImage: "shuffle") }
                }.disabled(rows.isEmpty).help("셔플")
            }
            .padding(.horizontal, compact ? 10 : 16).padding(.vertical, compact ? 6 : 10)

            if compact {
                List(rows, selection: $selection) { t in CompactTrackRow(track: t, showArtwork: showArtwork) }
                    .contextMenu(forSelectionType: Track.ID.self) { ids in menu(ids, rows) } primaryAction: { ids in playFrom(ids, in: rows) }
            } else {
            Table(rows, selection: $selection, sortOrder: $order, columnCustomization: $columns) {
                TableColumn("") { t in
                    if player.current?.id == t.id {
                        Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(.tint)
                    } else if t.loved {
                        Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
                    }
                }.width(22)
                .customizationID("icon").disabledCustomizationBehavior(.visibility)
                TableColumn("제목", value: \.title) { t in
                    HStack(spacing: 6) {
                        if showArtwork { ArtworkView(trackID: t.id, size: 22) }
                        Text(t.title).fontWeight(player.current?.id == t.id ? .semibold : .regular)
                    }
                }
                    .customizationID("title").disabledCustomizationBehavior(.visibility)
                TableColumn("아티스트", value: \.artist) { t in LinkCell(text: t.artist) { nav.showArtist(t) } }
                    .customizationID("artist")
                TableColumn("앨범", value: \.album) { t in LinkCell(text: t.album) { nav.showAlbum(t) } }
                    .customizationID("album")
                TableColumn("장르", value: \.genre).customizationID("genre").defaultVisibility(.hidden)
                TableColumn("연도", value: \.year) { t in Text(t.year > 0 ? "\(t.year)" : "").foregroundStyle(.secondary) }
                    .width(48).customizationID("year").defaultVisibility(.hidden)
                TableColumn("시간", value: \.duration) { t in Text(formatTime(t.duration)).monospacedDigit().foregroundStyle(.secondary) }
                    .width(56).customizationID("time")
                TableColumn("재생", value: \.playCount) { t in Text(t.playCount > 0 ? "\(t.playCount)" : "").foregroundStyle(.secondary) }
                    .width(44).customizationID("plays")
                TableColumn("수정일", value: \.modified) { t in Text(shortDate(Date(timeIntervalSince1970: t.modified))).foregroundStyle(.secondary) }
                    .width(min: 80, ideal: 120).customizationID("modified")
                TableColumn("추가일", value: \.dateAdded) { t in Text(shortDate(t.dateAdded)).foregroundStyle(.secondary) }
                    .width(min: 80, ideal: 120).customizationID("added").defaultVisibility(.hidden)
            }
            .contextMenu(forSelectionType: Track.ID.self) { ids in menu(ids, rows) } primaryAction: { ids in playFrom(ids, in: rows) }
            .draggable(selection.map { $0 }.joined(separator: "\n"))
            }
        }
        }
        .sheet(item: $editing) { req in TagEditor(ids: req.ids) }
        .onAppear { if let c = try? JSONDecoder().decode(TableColumnCustomization<Track>.self, from: columnsData) { columns = c } }
        .onChange(of: columns) { _, c in if let d = try? JSONEncoder().encode(c) { columnsData = d } }
    }

    private func summary(_ rows: [Track]) -> String { "\(rows.count)곡 · \(formatTime(rows.reduce(0) { $0 + $1.duration }))" }

    @ViewBuilder private func menu(_ ids: Set<String>, _ rows: [Track]) -> some View {
                if !ids.isEmpty {
                    Button("재생") { playFrom(ids, in: rows) }
                    Button(ids.count > 1 ? "정보 가져오기 (\(ids.count)곡)…" : "정보 가져오기…") { editing = EditRequest(ids: ordered(ids, rows)) }
                    if ids.count == 1, let t = library.track(ids.first!) {
                        Button("아티스트로 이동") { nav.showArtist(t) }
                        Button("앨범으로 이동") { nav.showAlbum(t) }
                    }
                    Divider()
                    Button("좋아요 표시/해제") { ids.forEach { library.toggleLoved($0) } }
                    Menu("플레이리스트에 추가") {
                        ForEach(library.playlists) { p in Button(p.name) { library.add(ordered(ids, rows), to: p.id) } }
                        Divider()
                        Button("새 플레이리스트…") { _ = library.newPlaylist(named: "새 플레이리스트", with: ordered(ids, rows)) }
                    }
                    if let playlist { Button("이 플레이리스트에서 빼기") { library.remove(ids, from: playlist) } }
                    Divider()
                    Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0) }) }
                }
    }

    private func ordered(_ ids: Set<String>, _ rows: [Track]) -> [String] { rows.map(\.id).filter { ids.contains($0) } }

    private func playFrom(_ ids: Set<String>, in rows: [Track]) {
        guard let first = rows.firstIndex(where: { ids.contains($0.id) }) else { return }
        player.play(rows.map(\.id), startAt: first)
    }
}

struct GroupBrowser: View {
    enum Kind { case artist, album }
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var nav: Navigator
    let kind: Kind
    let search: String
    private var picked: Binding<String?> { kind == .artist ? $nav.pickedArtist : $nav.pickedAlbum }

    private func key(_ t: Track) -> String { kind == .artist ? t.artistSort : t.albumSort }

    var body: some View {
        let groups = Dictionary(grouping: library.tracks, by: key)
        let names = groups.keys.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        HSplitView {
            ScrollViewReader { proxy in List(names, id: \.self, selection: picked) { name in
                HStack {
                    if kind == .album, let first = groups[name]?.first { ArtworkView(trackID: first.id, size: 28) }
                    VStack(alignment: .leading) {
                        Text(name).lineLimit(1)
                        if kind == .album, let a = groups[name]?.first?.artist { Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    Text("\(groups[name]?.count ?? 0)").foregroundStyle(.secondary).font(.caption)
                }
            }
            .onAppear { if let p = picked.wrappedValue { proxy.scrollTo(p, anchor: .center) } }

            .onChange(of: picked.wrappedValue) { _, p in
                guard let p else { return }
                DispatchQueue.main.async { withAnimation { proxy.scrollTo(p, anchor: .center) } }
            }
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)
            if let picked = picked.wrappedValue, let list = groups[picked] {
                TrackTable(title: picked, tracks: list.sorted { ($0.albumSort, $0.trackNumber, $0.title) < ($1.albumSort, $1.trackNumber, $1.title) })
                    .id(picked)
            } else {
                Text(kind == .artist ? "아티스트를 고르세요" : "앨범을 고르세요").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ArtworkView: View {
    @EnvironmentObject var library: LibraryStore
    let trackID: String?
    var size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
        .task(id: trackID) { image = nil; if let trackID { image = await library.artwork(for: trackID) } }
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var library: LibraryStore
    @State private var scrubbing: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            content(showExtras: w > 640, showSlider: w > 430, showInfo: w > 300)
                .frame(maxHeight: .infinity)
        }
        .frame(height: 56)
    }

    @ViewBuilder private func content(showExtras: Bool, showSlider: Bool, showInfo: Bool) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Button { player.previous() } label: { Image(systemName: "backward.fill") }
                Button { player.playPause() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 22) }
                Button { player.next() } label: { Image(systemName: "forward.fill") }
            }
            .buttonStyle(.borderless).font(.title3)

            if showInfo {
            HStack(spacing: 10) {
                ArtworkView(trackID: player.current?.id, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.title ?? "재생 중인 곡 없음").font(.callout.weight(.medium)).lineLimit(1)
                    HStack(spacing: 4) {
                        if let t = player.current {
                            Button(t.artist) { nav.showArtist(t) }.buttonStyle(.plain).help("아티스트로 이동")
                            if !t.album.isEmpty { Text("—"); Button(t.album) { nav.showAlbum(t) }.buttonStyle(.plain).help("앨범으로 이동") }
                        } else { Text(" ") }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if showSlider { ProgressRow(clock: player.clock) }
                }
                if let t = player.current {
                    Button { library.toggleLoved(t.id) } label: {
                        Image(systemName: (library.track(t.id)?.loved ?? false) ? "heart.fill" : "heart")
                    }.buttonStyle(.borderless).foregroundStyle(.pink)
                }
            }
            .frame(minWidth: 120, maxWidth: .infinity)
            } else { Spacer(minLength: 0) }

            HStack(spacing: 8) {
                if showExtras {
                Button { player.shuffle.toggle() } label: { Image(systemName: "shuffle") }
                    .foregroundStyle(player.shuffle ? Color.accentColor : .secondary)
                Button {
                    let all = RepeatMode.allCases
                    player.repeatMode = all[(all.firstIndex(of: player.repeatMode)! + 1) % all.count]
                } label: { Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat") }
                    .foregroundStyle(player.repeatMode == .off ? .secondary : Color.accentColor)
                Image(systemName: "speaker.fill").foregroundStyle(.secondary).font(.caption)
                Slider(value: $player.volume, in: 0...1).frame(width: 80).controlSize(.mini)
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

struct ConvertPanel: View {
    @EnvironmentObject var converter: Converter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(converter.busy ? "변환 중…" : "변환 완료").font(.headline)
                Spacer()
                if !converter.busy { Button("닫기") { converter.clearFinished() }.buttonStyle(.borderless) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(converter.jobs) { job in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.source.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                            switch job.state {
                            case .waiting: Text("대기 중").font(.caption2).foregroundStyle(.secondary)
                            case .working(let p): ProgressView(value: p).controlSize(.small)
                            case .done(let m): Label(m, systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green).lineLimit(1)
                            case .skipped(let m): Label(m, systemImage: "minus.circle").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            case .failed(let m): Label(m, systemImage: "xmark.octagon.fill").font(.caption2).foregroundStyle(.red).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            FolderSettings().tabItem { Label("보관함", systemImage: "folder") }
            SoundSettings().tabItem { Label("음량", systemImage: "speaker.wave.2") }
            LastFMSettings().tabItem { Label("Last.fm", systemImage: "dot.radiowaves.left.and.right") }
            ConvertSettings().tabItem { Label("변환", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 560, height: 360)
    }
}

struct FolderSettings: View {
    @EnvironmentObject var library: LibraryStore
    var body: some View {
        Form {
            Section("음악 폴더") {
                ForEach(library.folders, id: \.self) { f in
                    HStack {
                        Image(systemName: "folder")
                        Text(f.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("빼기") { library.folders.removeAll { $0 == f } }
                    }
                }
                HStack {
                    Button("폴더 추가…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
                        if panel.runModal() == .OK { library.folders.append(contentsOf: panel.urls.map(\.path).filter { !library.folders.contains($0) }) }
                    }
                    Button("다시 검색") { Task { await library.scan() } }.disabled(library.scanning)
                }
            }
            Section { Text("곡 \(library.tracks.count)개 · 플레이리스트 \(library.playlists.count)개").foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }
}

struct SoundSettings: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: LibraryStore
    @State private var hotKeysTick = 0
    var body: some View {
        Form {
            Section {
                Toggle("전역 단축키 (다른 앱을 쓰는 중에도 동작)", isOn: Binding(get: { GlobalHotKeys.shared.enabled }, set: { GlobalHotKeys.shared.enabled = $0; hotKeysTick += 1 }))
            } footer: {
                Text("⌃⌥P 재생/일시 정지 · ⌃⌥→ 다음 곡 · ⌃⌥← 이전 곡 · ⌃⌥↑/↓ 소리 크게/작게. 키보드의 재생·다음·이전 미디어 키도 어디서나 동작해요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("크로스페이드", selection: $player.crossfade) {
                    Text("끔").tag(0.0)
                    ForEach([2.0, 4, 6, 8, 10, 12], id: \.self) { s in Text("\(Int(s))초").tag(s) }
                }
            } footer: {
                Text("곡이 끝나기 전에 다음 곡을 겹쳐 시작해 자연스럽게 넘겨요. 자동으로 넘어갈 때만 적용되고, 직접 고른 곡이나 너무 짧은 곡은 바로 바뀌어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("음량 정규화 (곡마다 들리는 크기를 맞춤)", isOn: $player.normalize)
                Picker("목표 음량", selection: $player.targetLUFS) {
                    Text("-14 LUFS (스트리밍 서비스, 큼)").tag(-14.0)
                    Text("-16 LUFS (Apple Music, 기본)").tag(-16.0)
                    Text("-18 LUFS (조용함, 여유 많음)").tag(-18.0)
                    Text("-23 LUFS (방송 표준)").tag(-23.0)
                }.disabled(!player.normalize)
            } footer: {
                Text("곡마다 EBU R128 방식으로 실제 음량을 한 번 재 두고, 재생할 때 그만큼 키우거나 줄여요. 피크를 넘지 않게 해서 소리가 깨지지 않아요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("분석") {
                let measured = library.tracks.filter { $0.loudness != nil }.count
                if let a = library.analyzing {
                    ProgressView(value: Double(a.done), total: Double(max(1, a.total))) { Text("음량 분석 중 \(a.done)/\(a.total)") }
                } else {
                    Text("분석 끝난 곡 \(measured)/\(library.tracks.count)").foregroundStyle(.secondary)
                }
                if let t = player.current, player.normalize {
                    Text("지금 곡: \(t.loudness.map { String(format: "%.1f LUFS", $0) } ?? "분석 전") → 이득 \(String(format: "%+.1f dB", player.appliedGain))")
                        .font(.caption).monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct LastFMSettings: View {
    @EnvironmentObject var lastfm: LastFM
    var body: some View {
        Form {
            Section {
                if lastfm.connected {
                    LabeledContent("계정", value: lastfm.username ?? "연결됨")
                    Toggle("스크로블 보내기", isOn: $lastfm.enabled)
                    if lastfm.pendingCount > 0 { Text("보내지 못한 기록 \(lastfm.pendingCount)개 (인터넷이 되면 자동으로 보내요)").font(.caption) }
                    Button("연결 해제") { lastfm.disconnect() }
                } else {
                    TextField("API 키", text: $lastfm.apiKey)
                    SecureField("API 비밀(Shared secret)", text: $lastfm.apiSecret)
                    HStack {
                        Button("1. 연결 시작 (브라우저 열림)") { Task { await lastfm.beginAuth() } }
                        Button("2. 연결 마치기") { Task { await lastfm.finishAuth() } }
                    }
                    Link("API 키 만들기: last.fm/api/account/create", destination: URL(string: "https://www.last.fm/api/account/create")!).font(.caption)
                }
                if !lastfm.status.isEmpty { Text(lastfm.status).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("지금 듣는 곡을 표시하고, 30초 넘는 곡을 절반(최대 4분) 넘게 들으면 기록해요. 인터넷이 없을 때 들은 곡은 모아 뒀다가 나중에 보내요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ConvertSettings: View {
    @EnvironmentObject var converter: Converter
    var body: some View {
        Form {
            Section {
                Picker("무손실 원본(FLAC·WAV·AIFF)", selection: $converter.losslessTarget) {
                    ForEach(Converter.LosslessTarget.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("손실 원본(MP3 등)", value: "AAC 320kbps")
                LabeledContent("이미 m4a인 파일", value: "그대로 복사")
                LabeledContent("저장 위치") {
                    HStack {
                        Text(converter.destination.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle)
                        Button("바꾸기…") {
                            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                            if p.runModal() == .OK, let u = p.url { converter.destination = u.path }
                        }
                    }
                }
            } footer: {
                Text("음악 파일이나 폴더를 Sona 창에 끌어다 놓으면 바꿔서 저장 위치에 넣어요. 같은 이름의 곡이 이미 있으면 건너뛰어요. 태그와 앨범 아트도 옮겨요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct EditRequest: Identifiable { let id = UUID(); let ids: [String] }

private let shortDateFormatter: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "yyyy. M. d. HH:mm"; return f
}()
func shortDate(_ d: Date) -> String { shortDateFormatter.string(from: d) }

struct CompactTrackRow: View {
    @EnvironmentObject var player: Player
    let track: Track
    var showArtwork = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if player.current?.id == track.id {
                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(.tint).font(.caption)
                } else if track.loved {
                    Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption2)
                }
            }.frame(width: 16)
            if showArtwork { ArtworkView(trackID: track.id, size: 30) }
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).lineLimit(1).fontWeight(player.current?.id == track.id ? .semibold : .regular)
                Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(formatTime(track.duration)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}

struct ProgressRow: View {
    @EnvironmentObject var player: Player
    @ObservedObject var clock: PlaybackClock
    @State private var scrubbing: Double?

    var body: some View {
        HStack(spacing: 6) {
            Text(formatTime(scrubbing ?? clock.position)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            Slider(value: Binding(get: { scrubbing ?? clock.position }, set: { scrubbing = $0 }),
                   in: 0...max(1, player.duration)) { editing in
                if !editing, let s = scrubbing { player.seek(to: s); scrubbing = nil }
            }
            .controlSize(.mini)
            Text("-" + formatTime(max(0, player.duration - (scrubbing ?? clock.position)))).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
