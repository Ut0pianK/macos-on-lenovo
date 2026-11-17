import Foundation
import AVFoundation
import Accelerate
import MediaPlayer
import AppKit

enum RepeatMode: String, CaseIterable { case off, all, one }

@MainActor
final class Player: ObservableObject {
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false

    let clock = PlaybackClock()
    private(set) var position: Double {
        get { clock.position }
        set { clock.position = newValue }
    }
    @Published private(set) var duration: Double = 0
    @Published var volume: Float = UserDefaults.standard.object(forKey: "volume") as? Float ?? 0.8 {
        didSet { engine.mainMixerNode.outputVolume = volume; UserDefaults.standard.set(volume, forKey: "volume") }
    }
    @Published var normalize: Bool = UserDefaults.standard.bool(forKey: "normalize") {
        didSet {
            UserDefaults.standard.set(normalize, forKey: "normalize")
            if let t = current { applyGain(for: library?.track(t.id) ?? t) }
            if normalize { library?.analyzeLoudness() }
        }
    }

    @Published var targetLUFS: Double = UserDefaults.standard.object(forKey: "targetLUFS") as? Double ?? -16 {
        didSet { UserDefaults.standard.set(targetLUFS, forKey: "targetLUFS"); if let t = current { applyGain(for: library?.track(t.id) ?? t) } }
    }
    @Published private(set) var appliedGain: Double = 0
    @Published var shuffle = false { didSet { rebuildOrder(keepCurrent: true) } }
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var queue: [String] = []
    @Published private(set) var errorMessage: String?

    @Published var crossfade: Double = UserDefaults.standard.object(forKey: "crossfade") as? Double ?? 0 {
        didSet { UserDefaults.standard.set(crossfade, forKey: "crossfade") }
    }

    @MainActor private final class Deck {
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()
        let gain = AVAudioUnitEQ(numberOfBands: 0)
        var file: AVAudioFile?
        var format: AVAudioFormat?
        var segmentStart: AVAudioFramePosition = 0
    }

    private let engine = AVAudioEngine()
    private let decks = [Deck(), Deck()]
    private var active = 0
    private var deck: Deck { decks[active] }
    private var file: AVAudioFile? { deck.file }
    private var fadeTimer: Timer?
    private var fadeOut: Deck?
    private var generation = 0
    private var order: [Int] = []
    private var cursor = 0
    private var timer: Timer?
    private weak var library: LibraryStore?
    weak var lastfm: LastFM?
    private var scrobbled = false
    private var startedAt = Date()
    private var counted = false

    init() {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let bus = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 48000, channels: 2)
        for d in decks {
            engine.attach(d.player); engine.attach(d.mixer); engine.attach(d.gain)
            engine.connect(d.player, to: d.mixer, format: nil)
            engine.connect(d.mixer, to: d.gain, format: bus)
            engine.connect(d.gain, to: engine.mainMixerNode, format: bus)
        }
        engine.mainMixerNode.outputVolume = volume
        setupRemoteCommands()
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func attach(_ library: LibraryStore) {
        self.library = library
        NotificationCenter.default.addObserver(forName: .sonaLoudnessUpdated, object: nil, queue: .main) { [weak self] n in
            Task { @MainActor in
                guard let self, let id = n.object as? String, self.current?.id == id, let t = self.library?.track(id) else { return }
                self.applyGain(for: t)
            }
        }
    }

    private func applyGain(for track: Track) {
        var g = 0.0
        if normalize, let l = track.loudness { g = LoudnessMeter.gain(lufs: l, peak: track.peak ?? 1, target: targetLUFS) }
        deck.gain.globalGain = Float(g)
        appliedGain = g
    }

    func play(_ ids: [String], startAt start: Int = 0) {
        guard !ids.isEmpty else { return }
        queue = ids
        order = Array(ids.indices)
        if shuffle {
            var rest = order.filter { $0 != start }; rest.shuffle()
            order = [start] + rest; cursor = 0
        } else { cursor = start }
        load(index: order[cursor], autoplay: true)
    }

    private func rebuildOrder(keepCurrent: Bool) {
        guard !queue.isEmpty else { return }
        let cur = order.isEmpty ? 0 : order[cursor]
        if shuffle {
            var rest = queue.indices.filter { $0 != cur }; rest.shuffle()
            order = [cur] + rest; cursor = 0
        } else {
            order = Array(queue.indices); cursor = cur
        }
    }

    func playPause() {
        if current == nil {
            if let lib = library, !lib.tracks.isEmpty { play(lib.tracks.map(\.id)) }
            return
        }
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        finishFade()
        deck.player.pause(); engine.pause(); isPlaying = false; updateNowPlaying()
    }

    func resume() {
        guard file != nil else { return }
        guard startEngine() else { return }
        deck.player.play(); isPlaying = true; updateNowPlaying()
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        do { try engine.start(); return true } catch {
            isPlaying = false
            errorMessage = "오디오 장치를 열 수 없음: \(error.localizedDescription)"
            updateNowPlaying()
            return false
        }
    }

    func next(auto: Bool = false, fade: Bool = false) {
        guard !order.isEmpty else { return }
        if auto && repeatMode == .one { seek(to: 0); if !isPlaying { resume() }; return }
        if cursor + 1 < order.count {
            cursor += 1
        } else if repeatMode == .all || !auto {

            if shuffle { rebuildOrder(keepCurrent: false) }
            cursor = 0
        } else {
            stopAtEnd(); return
        }
        load(index: order[cursor], autoplay: true, fade: fade)
    }

    private var hasAutoNext: Bool {
        repeatMode != .one && (cursor + 1 < order.count || repeatMode == .all)
    }

    func previous() {
        if position > 3 { seek(to: 0); return }
        guard !order.isEmpty else { return }
        cursor = cursor > 0 ? cursor - 1 : (repeatMode == .all ? order.count - 1 : 0)
        load(index: order[cursor], autoplay: true)
    }

    private func stopAtEnd() {
        finishFade()
        deck.player.stop(); isPlaying = false; position = duration; deck.segmentStart = 0
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        finishFade()
        guard let file else { return }
        let sr = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(max(0, min(seconds, duration - 0.05)) * sr)
        let wasPlaying = isPlaying
        generation += 1
        deck.player.stop()
        schedule(file: file, from: frame)
        position = Double(frame) / sr
        if wasPlaying {

            guard startEngine() else { return }
            deck.player.play()
        }
        updateNowPlaying()
    }

    private func load(index: Int, autoplay: Bool, fade: Bool = false) {
        guard index < queue.count, let lib = library, let track = lib.track(queue[index]) else { return }
        let f: AVAudioFile
        do { f = try AVAudioFile(forReading: track.url) } catch {
            errorMessage = "열 수 없는 파일: \(track.url.lastPathComponent)"

            if cursor + 1 < order.count { cursor += 1; load(index: order[cursor], autoplay: autoplay, fade: fade) }
            updateNowPlaying()
            return
        }
        generation += 1
        let crossfading = fade && isPlaying && engine.isRunning
        if crossfading {
            finishFade()
            fadeOut = deck
            active ^= 1
        } else {
            finishFade()
        }
        let d = deck
        d.player.stop()
        d.player.volume = crossfading ? 0 : 1
        d.file = f
        if d.format != f.processingFormat {

            engine.disconnectNodeOutput(d.player)
            engine.connect(d.player, to: d.mixer, format: f.processingFormat)
            d.format = f.processingFormat
        }
        current = track
        duration = Double(f.length) / f.processingFormat.sampleRate
        position = 0
        counted = false
        scrobbled = false
        startedAt = Date()
        lastfm?.nowPlaying(track)
        errorMessage = nil
        applyGain(for: track)
        if normalize, track.loudness == nil { library?.analyzeLoudness(first: track.id) }
        schedule(file: f, from: 0)
        if crossfading {
            d.player.play()
            startFade(seconds: crossfade)
        } else if autoplay { resume() }
        updateNowPlaying()
    }

    private func startFade(seconds: Double) {
        guard let out = fadeOut else { return }
        let incoming = deck
        let start = Date()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = min(1, Date().timeIntervalSince(start) / max(0.1, seconds))

                out.player.volume = Float(cos(t * .pi / 2))
                incoming.player.volume = Float(sin(t * .pi / 2))
                if t >= 1 { self.finishFade() }
            }
        }
    }

    private func finishFade() {
        fadeTimer?.invalidate(); fadeTimer = nil
        if let out = fadeOut { out.player.stop(); out.player.volume = 1; out.file = nil }
        fadeOut = nil
        deck.player.volume = 1
    }

    private func schedule(file: AVAudioFile, from frame: AVAudioFramePosition) {
        let d = deck
        d.segmentStart = frame
        let remaining = AVAudioFrameCount(max(0, file.length - frame))
        guard remaining > 0 else { return }
        let gen = generation
        let player = self
        d.player.scheduleSegment(file, startingFrame: frame, frameCount: remaining, at: nil,
                                 completionCallbackType: .dataPlayedBack) { @Sendable _ in

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard player.generation == gen else { return }
                    player.next(auto: true)
                }
            }
        }
    }

    private func tick() {
        let d = deck
        if isPlaying, let file = d.file, let nt = d.player.lastRenderTime, let pt = d.player.playerTime(forNodeTime: nt) {
            position = min(duration, Double(d.segmentStart + pt.sampleTime) / file.processingFormat.sampleRate)
            if !counted && duration > 0 && position >= duration * 0.8, let id = current?.id { counted = true; library?.markPlayed(id) }
            if !scrobbled, duration > 30, position >= min(240, duration * 0.5), let t = current { scrobbled = true; lastfm?.scrobble(t, startedAt: startedAt) }

            if crossfade > 0, fadeOut == nil, hasAutoNext, duration > crossfade * 2 + 2,
               position >= duration - crossfade {
                next(auto: true, fade: true)
            }
        }
    }

    private func handleConfigurationChange() {

        let pos = position, was = isPlaying
        if file != nil { seek(to: pos) }
        if was { resume() } else { isPlaying = false }
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.playPause() }; return .success }
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { Task { @MainActor in self?.seek(to: e.positionTime) } }
            return .success
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let t = current else { center.nowPlayingInfo = nil; center.playbackState = .stopped; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        let id = t.id
        Task { @MainActor [weak self] in
            guard let self, let img = await self.library?.artwork(for: id), self.current?.id == id else { return }

            let handler: @Sendable (CGSize) -> NSImage = { [img] _ in img }
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size, requestHandler: handler)
            center.nowPlayingInfo = info
        }
    }
}

@MainActor
final class PlaybackClock: ObservableObject {
    @Published var position: Double = 0
}
