import Foundation
import AVFoundation

/// بزوێنەری دەنگ — سەرجەم دەنگەکان بە کۆد دروستدەکرێن (بێ فایلی دەرەکی)
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let shotPlayer = AVAudioPlayerNode()
    private let fxPlayer = AVAudioPlayerNode()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    var volume: Float = 0.8 {
        didSet {
            shotPlayer.volume = volume
            fxPlayer.volume = volume * 0.7
        }
    }

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.attach(shotPlayer)
        engine.attach(fxPlayer)
        engine.connect(shotPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(fxPlayer, to: engine.mainMixerNode, format: format)
        buffers["akm"] = makeShotBuffer(format: format, low: 90, decay: 0.16, gain: 0.9)
        buffers["m416"] = makeShotBuffer(format: format, low: 220, decay: 0.11, gain: 0.75)
        buffers["hit"] = makePingBuffer(format: format, freq: 1150, duration: 0.06)
        buffers["kill"] = makeChirpBuffer(format: format, f0: 900, f1: 380, duration: 0.22)
        buffers["hurt"] = makePingBuffer(format: format, freq: 240, duration: 0.12)
        buffers["reload"] = makeClickBuffer(format: format)
        try? engine.start()
    }

    enum FX { case shotAKM, shotM416, hit, kill, hurt, reload }

    func play(_ fx: FX) {
        let node: AVAudioPlayerNode
        let key: String
        switch fx {
        case .shotAKM: node = shotPlayer; key = "akm"
        case .shotM416: node = shotPlayer; key = "m416"
        case .hit: node = fxPlayer; key = "hit"
        case .kill: node = fxPlayer; key = "kill"
        case .hurt: node = fxPlayer; key = "hurt"
        case .reload: node = fxPlayer; key = "reload"
        }
        guard let buf = buffers[key] else { return }
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    // MARK: - دروستکردنی دەنگەکان بە ماتماتیک

    private func makeShotBuffer(format: AVAudioFormat, low: Float, decay: Float, gain: Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(44100 * decay)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        let data = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Float(i) / 44100
            let env = exp(-t / (decay * 0.28))
            let noise = Float.random(in: -1...1)
            let thump = sin(2 * .pi * low * t) * env * 0.8
            data[i] = (noise * env * 0.75 + thump) * gain
        }
        return buf
    }

    private func makePingBuffer(format: AVAudioFormat, freq: Float, duration: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(44100 * duration)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        let data = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Float(i) / 44100
            let env = exp(-t / (Float(duration) * 0.3))
            data[i] = sin(2 * .pi * freq * t) * env * 0.5
        }
        return buf
    }

    private func makeChirpBuffer(format: AVAudioFormat, f0: Float, f1: Float, duration: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(44100 * duration)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        let data = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Float(i) / 44100
            let prog = t / Float(duration)
            let freq = f0 + (f1 - f0) * prog
            let env = exp(-t / (Float(duration) * 0.35))
            data[i] = sin(2 * .pi * freq * t) * env * 0.5
        }
        return buf
    }

    private func makeClickBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(44100 * 0.35)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        let data = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Float(i) / 44100
            let click = sin(2 * .pi * 1800 * t) * exp(-t / 0.01) * 0.4
            let click2 = sin(2 * .pi * 1500 * max(0, t - 0.18)) * exp(-max(0, t - 0.18) / 0.01) * 0.4
            data[i] = click + click2
        }
        return buf
    }
}
