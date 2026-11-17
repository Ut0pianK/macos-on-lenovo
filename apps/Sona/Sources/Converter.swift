import Foundation
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class Converter: ObservableObject {
    enum LosslessTarget: String, CaseIterable, Identifiable {
        case alac, aac
        var id: String { rawValue }
        var title: String { self == .alac ? "ALAC 무손실 (파일 큼)" : "AAC 320kbps (기존 곡과 같은 방식)" }
    }

    struct Job: Identifiable {
        enum State: Equatable { case waiting, working(Double), done(String), skipped(String), failed(String) }
        let id = UUID()
        let source: URL
        var state: State = .waiting
    }

    @Published private(set) var jobs: [Job] = []
    @Published var losslessTarget: LosslessTarget = LosslessTarget(rawValue: UserDefaults.standard.string(forKey: "conv.lossless") ?? "") ?? .alac {
        didSet { UserDefaults.standard.set(losslessTarget.rawValue, forKey: "conv.lossless") }
    }
    @Published var destination: String = UserDefaults.standard.string(forKey: "conv.dest") ?? LibraryStore.iCloudMusic {
        didSet { UserDefaults.standard.set(destination, forKey: "conv.dest") }
    }
    var busy: Bool { jobs.contains { if case .waiting = $0.state { return true }; if case .working = $0.state { return true }; return false } }

    private var running = false
    weak var library: LibraryStore?

    static let inputExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "wave", "aif", "aiff", "aifc", "flac", "caf", "alac", "m4b", "mp4"]

    func clearFinished() { jobs.removeAll { if case .waiting = $0.state { return false }; if case .working = $0.state { return false }; return true } }

    func enqueue(_ urls: [URL]) {
        var files: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let en = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let f = en?.nextObject() as? URL {
                    if Self.inputExtensions.contains(f.pathExtension.lowercased()) { files.append(f) }
                }
            } else {
                files.append(u)
            }
        }
        for f in files {
            var job = Job(source: f)
            if !Self.inputExtensions.contains(f.pathExtension.lowercased()) { job.state = .skipped("지원하지 않는 형식") }
            jobs.append(job)
        }
        runQueue()
    }

    private func runQueue() {
        guard !running else { return }
        running = true
        Task {
            while let i = jobs.firstIndex(where: { $0.state == .waiting }) {
                jobs[i].state = .working(0)
                let id = jobs[i].id
                let src = jobs[i].source
                let dest = URL(fileURLWithPath: destination, isDirectory: true)
                let target = losslessTarget
                let result = await Converter.convert(src, into: dest, lossless: target) { p in
                    Task { @MainActor in if let k = self.jobs.firstIndex(where: { $0.id == id }), case .working = self.jobs[k].state { self.jobs[k].state = .working(p) } }
                }
                if let k = jobs.firstIndex(where: { $0.id == id }) { jobs[k].state = result }
            }
            running = false
            await library?.scan()
        }
    }

    nonisolated static func convert(_ src: URL, into folder: URL, lossless: LosslessTarget,
                                    progress: @escaping @Sendable (Double) -> Void) async -> Job.State {
        let asset = AVURLAsset(url: src)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return .failed("오디오를 읽을 수 없음") }
        let descs = (try? await track.load(.formatDescriptions)) ?? []
        guard let desc = descs.first, let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return .failed("형식을 알 수 없음") }
        let asbd = asbdPtr.pointee
        let codec = asbd.mFormatID
        let isLossless = [kAudioFormatLinearPCM, kAudioFormatAppleLossless, kAudioFormatFLAC].contains(codec)
        let alreadyM4A = ["m4a", "mp4", "m4b"].contains(src.pathExtension.lowercased()) && (codec == kAudioFormatMPEG4AAC || codec == kAudioFormatAppleLossless)

        let meta = (try? await asset.load(.metadata)) ?? []
        let common = (try? await asset.load(.commonMetadata)) ?? []
        func value(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: id).first else { return nil }
            return try? await item.load(.stringValue)
        }
        let title = await value(.commonIdentifierTitle) ?? src.deletingPathExtension().lastPathComponent
        let artist = await value(.commonIdentifierArtist)
        var name = artist.map { "\($0) - \(title)" } ?? title
        name = name.replacingOccurrences(of: "/", with: "／").replacingOccurrences(of: ":", with: "：")
        var out = folder.appendingPathComponent(name).appendingPathExtension("m4a")
        if FileManager.default.fileExists(atPath: out.path) { return .skipped("이미 있음: \(out.lastPathComponent)") }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        if alreadyM4A {
            do { try FileManager.default.copyItem(at: src, to: out); progress(1); return .done("복사함(재인코딩 없음): \(out.lastPathComponent)") }
            catch { return .failed("복사 실패: \(error.localizedDescription)") }
        }

        let useALAC = isLossless && lossless == .alac
        let channels = max(1, min(Int(asbd.mChannelsPerFrame), 2))
        var rate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 44100
        if !useALAC { rate = min(rate, 48000) }
        let srcBits: UInt32 = codec == kAudioFormatLinearPCM ? asbd.mBitsPerChannel : (asbd.mFormatFlags >= 3 ? 24 : 16)
        let bits = useALAC ? (srcBits >= 24 ? 24 : 16) : 32

        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bits, AVLinearPCMIsFloatKey: !useALAC,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ]
        let writerSettings: [String: Any] = useALAC
            ? [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels, AVEncoderBitDepthHintKey: bits]
            : [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
               AVEncoderBitRateKey: channels == 1 ? 192_000 : 320_000, AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue]

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
            reader.add(output)
            let writer = try AVAssetWriter(outputURL: tmp, fileType: .m4a)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
            input.expectsMediaDataInRealTime = false
            writer.add(input)

            writer.metadata = await m4aMetadata(common: common, all: meta)

            guard reader.startReading(), writer.startWriting() else {
                return .failed("변환 시작 실패: \((reader.error ?? writer.error)?.localizedDescription ?? "")")
            }
            writer.startSession(atSourceTime: .zero)
            let total = (try? await asset.load(.duration).seconds) ?? 0
            let queue = DispatchQueue(label: "sona.convert")
            let finished: Bool = await withCheckedContinuation { cont in
                input.requestMediaDataWhenReady(on: queue) {
                    while input.isReadyForMoreMediaData {
                        if let buf = output.copyNextSampleBuffer() {
                            if !input.append(buf) { reader.cancelReading(); input.markAsFinished(); cont.resume(returning: false); return }
                            if total > 0 { progress(min(1, CMSampleBufferGetPresentationTimeStamp(buf).seconds / total)) }
                        } else {
                            input.markAsFinished()
                            cont.resume(returning: reader.status == .completed)
                            return
                        }
                    }
                }
            }
            guard finished else { writer.cancelWriting(); return .failed("변환 중 오류: \((reader.error ?? writer.error)?.localizedDescription ?? "")") }
            await writer.finishWriting()
            guard writer.status == .completed else { return .failed("저장 실패: \(writer.error?.localizedDescription ?? "")") }
            if FileManager.default.fileExists(atPath: out.path) { out = folder.appendingPathComponent(name + " (2)").appendingPathExtension("m4a") }
            try FileManager.default.moveItem(at: tmp, to: out)
            progress(1)
            return .done((useALAC ? "ALAC" : "AAC 320k") + ": \(out.lastPathComponent)")
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return .failed(error.localizedDescription)
        }
    }
}

func m4aMetadata(common: [AVMetadataItem], all: [AVMetadataItem]) async -> [AVMetadataItem] {
    var out: [AVMetadataItem] = []
    func add(_ id: AVMetadataIdentifier, _ value: (NSCopying & NSObjectProtocol)?, dataType: String? = nil) {
        guard let value else { return }
        let m = AVMutableMetadataItem()
        m.identifier = id; m.value = value
        if let dataType { m.dataType = dataType }
        out.append(m)
    }
    func str(_ id: AVMetadataIdentifier) async -> String? {
        guard let i = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: id).first else { return nil }
        return try? await i.load(.stringValue)
    }
    add(.iTunesMetadataSongName, await str(.commonIdentifierTitle) as NSString?)
    add(.iTunesMetadataArtist, await str(.commonIdentifierArtist) as NSString?)
    add(.iTunesMetadataAlbum, await str(.commonIdentifierAlbumName) as NSString?)
    add(.iTunesMetadataUserGenre, await str(.commonIdentifierType) as NSString?)
    add(.iTunesMetadataCopyright, await str(.commonIdentifierCopyrights) as NSString?)
    add(.iTunesMetadataComposer, await str(.commonIdentifierCreator) as NSString?)
    if let d = await str(.commonIdentifierCreationDate) { add(.iTunesMetadataReleaseDate, d as NSString) }

    for item in all {
        guard let id = item.identifier?.rawValue else { continue }
        if id.hasSuffix("/TPE2") || id.hasSuffix("/aART") || id.lowercased().hasSuffix("albumartist") {
            if let s = try? await item.load(.stringValue) { add(.iTunesMetadataAlbumArtist, s as NSString) }
        } else if id.hasSuffix("/TRCK") || id.lowercased().hasSuffix("tracknumber") {
            if let s = try? await item.load(.stringValue) {
                let parts = s.split(separator: "/").compactMap { UInt16($0.trimmingCharacters(in: .whitespaces)) }
                if let n = parts.first {
                    let total = parts.count > 1 ? parts[1] : 0
                    let bytes: [UInt8] = [0, 0, UInt8(n >> 8), UInt8(n & 0xff), UInt8(total >> 8), UInt8(total & 0xff), 0, 0]
                    add(.iTunesMetadataTrackNumber, Data(bytes) as NSData, dataType: kCMMetadataBaseDataType_RawData as String)
                }
            }
        } else if item.keySpace == .iTunes, id.hasSuffix("/trkn") || id.hasSuffix("/disk") || id.hasSuffix("/aART") {
            out.append(item)
        }
    }
    if let art = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork).first,
       let data = try? await art.load(.dataValue) {
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        add(.iTunesMetadataCoverArt, data as NSData,
            dataType: (isPNG ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG) as String)
    }
    return out
}
