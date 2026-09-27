import AVFoundation
import Foundation
import Speech

/// Push-to-talk for the palette: microphone → on-device SpeechAnalyzer → live text in the field; the request runs
/// when you pause. Nothing is recorded to disk and nothing leaves the Mac.
@MainActor
final class Voice: ObservableObject {
    static let shared = Voice()
    @Published private(set) var isListening = false
    @Published private(set) var level: Float = 0
    @Published var problem: String?

    var onText: (String) -> Void = { _ in }
    var onFinish: (String) -> Void = { _ in }

    static let pause: TimeInterval = 1.4
    static let maxSilence: TimeInterval = 8

    private var engine: AVAudioEngine?
    private var live: LiveTranscription?
    private var watcher: Task<Void, Never>?
    private var text = ""
    private var lastChange = Date()

    func toggle() { if isListening { Task { await stop(submit: true) } } else { Task { await start() } } }

    func start() async {
        guard !isListening else { return }
        problem = nil
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            problem = "Microphone access is off for Muon. Allow it in System Settings › Privacy & Security › Microphone."; return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { problem = "No microphone found."; return }
        let live: LiveTranscription
        do { live = try await LiveTranscription(sourceFormat: format) } catch { problem = "Speech recognition unavailable: \(error.localizedDescription)"; return }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            live.feed(buffer)
            let lvl = LiveTranscription.level(of: buffer)
            Task { @MainActor in self?.level = lvl }
        }
        do { engine.prepare(); try engine.start() } catch { input.removeTap(onBus: 0); problem = "Could not start the microphone: \(error.localizedDescription)"; return }
        self.engine = engine; self.live = live
        text = ""; lastChange = Date(); isListening = true
        Task { [weak self] in
            for await t in live.texts { await MainActor.run { self?.heard(t) } }
        }
        watcher = Task { [weak self] in
            while let self, self.isListening, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                let quiet = Date().timeIntervalSince(self.lastChange)
                if (!self.text.isEmpty && quiet > Self.pause) || (self.text.isEmpty && quiet > Self.maxSilence) { await self.stop(submit: true); break }
            }
        }
    }

    private func heard(_ t: String) {
        guard isListening, t != text else { return }
        text = t; lastChange = Date(); onText(t)
    }

    /// Stops listening. `submit` hands the final text to `onFinish`; false just cancels.
    func stop(submit: Bool) async {
        guard isListening, let engine, let live else { return }
        isListening = false; level = 0
        watcher?.cancel(); watcher = nil
        engine.inputNode.removeTap(onBus: 0); engine.stop()
        self.engine = nil; self.live = nil
        let final = await live.finish()
        let result = (final.isEmpty ? text : final).trimmingCharacters(in: .whitespacesAndNewlines)
        if submit { onFinish(result) }
    }

    func cancel() { Task { await stop(submit: false) } }
}

/// One streaming SpeechAnalyzer session fed from audio buffers (microphone or a file, for tests).
final class LiveTranscription: @unchecked Sendable {
    let texts: AsyncStream<String>
    private let textsCont: AsyncStream<String>.Continuation
    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let format: AVAudioFormat
    private let converter: AVAudioConverter?
    private let lock = NSLock()
    private var latest = ""
    private var collector: Task<Void, Never>?

    init(sourceFormat: AVAudioFormat) async throws {
        transcriber = SpeechTranscriber(locale: Locale.current, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        analyzer = SpeechAnalyzer(modules: [transcriber])
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await req.downloadAndInstall() }
        guard let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw IntelligenceError.noInput("The speech model has no usable audio format.") }
        format = best
        converter = sourceFormat.sampleRate == best.sampleRate && sourceFormat.channelCount == best.channelCount && sourceFormat.commonFormat == best.commonFormat ? nil : AVAudioConverter(from: sourceFormat, to: best)
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        input = cont
        (texts, textsCont) = AsyncStream<String>.makeStream()
        try await analyzer.start(inputSequence: stream)
        collector = Task { [transcriber, textsCont, weak self] in
            var final = ""
            do {
                for try await r in transcriber.results {
                    let t = String(r.text.characters)
                    let shown = r.isFinal ? { final += t; return final }() : final + t
                    self?.set(shown)
                    textsCont.yield(shown)
                }
            } catch { /* finished or cancelled */ }
            textsCont.finish()
        }
    }

    private func set(_ s: String) { lock.lock(); latest = s; lock.unlock() }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { input.yield(AnalyzerInput(buffer: buffer)); return }
        let ratio = format.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32) else { return }
        var consumed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData; return buffer
        }
        if err == nil, out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
    }

    /// Ends the input, waits for the last results, returns the full text.
    func finish() async -> String {
        input.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        // The results stream normally ends here; cap the wait so a stuck stream can never hang the palette.
        if let collector { Task { try? await Task.sleep(for: .seconds(2)); collector.cancel() }; await collector.value }
        lock.lock(); defer { lock.unlock() }
        return latest.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// RMS level 0…1 for the mic indicator.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += ch[i] * ch[i] }
        return min(1, sqrt(sum / Float(buffer.frameLength)) * 6)
    }

    /// Feeds a whole audio file through the live path (what the microphone does), for tests and diagnostics.
    static func transcribe(file path: String) async throws -> String {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let live = try await LiveTranscription(sourceFormat: file.processingFormat)
        let chunk: AVAudioFrameCount = 8192
        while file.framePosition < file.length {
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
            try file.read(into: buf, frameCount: chunk)
            if buf.frameLength == 0 { break }
            live.feed(buf)
        }
        return await live.finish()
    }
}

/// Spoken replies for spoken requests.
@MainActor
enum Speaker {
    private static let synth = AVSpeechSynthesizer()

    static func speak(_ text: String) {
        stop()
        let short = String(text.prefix(600))
        guard !short.isEmpty else { return }
        let u = AVSpeechUtterance(string: short)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    static func stop() { if synth.isSpeaking { synth.stopSpeaking(at: .immediate) } }
}
