import Foundation
import AVFoundation
import Accelerate

enum LoudnessMeter {
    struct Result { var lufs: Double; var peak: Double }

    private struct Biquad {
        var b0, b1, b2, a1, a2: Double
        var z1 = 0.0, z2 = 0.0
        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private static func kWeighting(_ fs: Double) -> (Biquad, Biquad) {
        var f0 = 1681.974450955533, G = 3.999843853973347, Q = 0.7071752369554196
        var K = tan(.pi * f0 / fs)
        let Vh = pow(10, G / 20), Vb = pow(Vh, 0.4996667741545416)
        var a0 = 1 + K / Q + K * K
        let shelf = Biquad(b0: (Vh + Vb * K / Q + K * K) / a0, b1: 2 * (K * K - Vh) / a0, b2: (Vh - Vb * K / Q + K * K) / a0,
                           a1: 2 * (K * K - 1) / a0, a2: (1 - K / Q + K * K) / a0)
        f0 = 38.13547087602444; Q = 0.5003270373238773; G = 0
        K = tan(.pi * f0 / fs)
        a0 = 1 + K / Q + K * K
        let hp = Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (K * K - 1) / a0, a2: (1 - K / Q + K * K) / a0)
        return (shelf, hp)
    }

    static func measure(url: URL) -> Result? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let fmt = file.processingFormat
        let fs = fmt.sampleRate
        let channels = min(Int(fmt.channelCount), 2)
        guard channels > 0, fs > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 65536) else { return nil }

        var filters = (0..<channels).map { _ in kWeighting(fs) }
        let block = Int(fs * 0.4), hop = Int(fs * 0.1)
        var hopSums = [Double]()
        var acc = 0.0, accN = 0
        var peak: Float = 0

        while file.framePosition < file.length {
            do { try file.read(into: buf) } catch { break }
            let n = Int(buf.frameLength)
            if n == 0 { break }
            guard let data = buf.floatChannelData else { break }
            for c in 0..<channels {
                var m: Float = 0; vDSP_maxmgv(data[c], 1, &m, vDSP_Length(n)); peak = max(peak, m)
            }
            for i in 0..<n {
                var s = 0.0
                for c in 0..<channels {
                    var x = Double(data[c][i])
                    x = filters[c].0.process(x); x = filters[c].1.process(x)
                    s += x * x
                }
                acc += s; accN += 1
                if accN == hop { hopSums.append(acc / Double(hop)); acc = 0; accN = 0 }
            }
        }
        let per = block / hop
        guard hopSums.count >= per else { return nil }
        var blocks = [Double]()
        for i in 0...(hopSums.count - per) { blocks.append(hopSums[i..<(i + per)].reduce(0, +) / Double(per)) }
        func lufs(_ z: Double) -> Double { -0.691 + 10 * log10(max(z, 1e-12)) }
        let abs = blocks.filter { lufs($0) > -70 }
        guard !abs.isEmpty else { return Result(lufs: -70, peak: Double(peak)) }
        let gate = lufs(abs.reduce(0, +) / Double(abs.count)) - 10
        let rel = abs.filter { lufs($0) > gate }
        let z = rel.isEmpty ? abs.reduce(0, +) / Double(abs.count) : rel.reduce(0, +) / Double(rel.count)
        return Result(lufs: lufs(z), peak: Double(peak))
    }

    static func gain(lufs: Double, peak: Double, target: Double) -> Double {
        var g = target - lufs
        if peak > 0 { g = min(g, -20 * log10(peak) - 0.5) }
        return max(-15, min(12, g))
    }
}
