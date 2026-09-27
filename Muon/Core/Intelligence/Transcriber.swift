import AVFoundation
import Foundation
import Speech

/// On-device transcription with the macOS 26 SpeechAnalyzer, plus meeting notes.
enum Transcriber {
    static let audioExts: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "mov", "mp4", "m4v", "aac", "flac"]

    static func transcribe(_ path: String, status: @escaping (String) -> Void) async throws -> String {
        let real = try PathPolicy.resolve(path)
        guard audioExts.contains((real as NSString).pathExtension.lowercased()) else { throw IntelligenceError.noInput("That isn't an audio or video file.") }
        let locale = Locale.current
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            status("Downloading the on-device speech model (one time)…")
            try await req.downloadAndInstall()
        }
        status("Transcribing \((real as NSString).lastPathComponent)…")
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: real))
        async let collected: String = {
            var text = ""
            for try await result in transcriber.results { text += String(result.text.characters) }
            return text
        }()
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let text = try await collected.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw IntelligenceError.noInput("No speech was recognized in that file.") }
        return text
    }

    static func meetingNotes(_ transcript: String, status: @escaping (String) -> Void) async throws -> String {
        try await TextTools.generate(instruction: "These are meeting or voice-note transcript words. Write: a 3-5 sentence summary; then 'Decisions:' as bullets; then 'Action items:' as bullets with the owner if mentioned. If a section has nothing, write 'none'.", input: transcript, status: status)
    }

    static let tools: [HostTool] = [
        HostTool(name: "transcribeAudio", description: "Transcribe an audio or video file to text, on-device (m4a, mp3, wav, mov, mp4…).",
                 schema: HostTool.schema([("path", "string", "File path")], required: ["path"]), readOnly: true, destructive: false) { a in
            try await transcribe(HostTools.string(a, "path"), status: { _ in })
        },
        HostTool(name: "meetingNotes", description: "Transcribe a recording and turn it into meeting notes: summary, decisions, action items.",
                 schema: HostTool.schema([("path", "string", "Audio/video file")], required: ["path"]), readOnly: true, destructive: false) { a in
            let t = try await transcribe(HostTools.string(a, "path"), status: { _ in })
            return try await meetingNotes(t, status: { _ in })
        },
    ]
}
