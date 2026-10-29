import Foundation
import WhisperKit

/// On-device speech-to-text with WhisperKit, using the language-adaptive prompting chosen in
/// Phase 0 (PLAN §5):
/// 1. Detect the language (unless the user fixed it to English or Korean).
/// 2. English → prompt with the vocabulary list. Korean (incl. mixed) → short mixed sample only.
/// 3. If Korean was detected but the result has no Hangul, Whisper translated: re-run without a prompt.
actor Transcriber {
    static let modelName = "large-v3-v20240930_turbo_632MB"
    static let modelDisplayName = "Whisper large-v3 turbo"
    static let modelSizeMB = 632

    /// Short mixed sample in a dictation style. Keeps English terms in Latin script inside Korean
    /// sentences. Keep it short: adding an English word list here made Whisper translate Korean.
    static let mixedPrompt = "오늘 meeting에서 project timeline 얘기했고, API 관련 bug는 다음 sprint에 fix 할게요."

    struct Options: Sendable {
        var language: AppSettingsLanguage
        var keepEnglishInKorean: Bool
        /// English terms from the Dictionary, used as the prompt for English dictations.
        var vocabulary: [String]
    }

    enum AppSettingsLanguage: Sendable { case auto, english, korean }

    struct Result: Sendable {
        let text: String
        let language: String
    }

    private var whisper: WhisperKit?

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalFlow/Models", isDirectory: true)
    }

    static var modelFolder: URL {
        modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)", isDirectory: true)
    }

    static var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent("AudioEncoder.mlmodelc").path)
    }

    /// Downloads the model if needed (reporting 0…1 progress), loads it, and warms it up so the
    /// first real dictation isn't slow.
    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard whisper == nil else { return }
        try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)

        let folder: URL
        if Self.isModelDownloaded {
            folder = Self.modelFolder
        } else {
            folder = try await WhisperKit.download(variant: Self.modelName, downloadBase: Self.modelsDirectory) { p in
                progress(p.fractionCompleted)
            }
        }
        progress(1)

        let config = WhisperKitConfig(
            downloadBase: Self.modelsDirectory,
            modelFolder: folder.path,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine
            ),
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        let whisper = try await WhisperKit(config)
        _ = try? await whisper.transcribe(audioArray: [Float](repeating: 0, count: 16_000))
        self.whisper = whisper
    }

    func transcribe(_ audio: [Float], options: Options) async throws -> Result {
        guard let whisper else { throw TranscriberError.notLoaded }

        let forced: String? = switch options.language {
        case .auto: nil
        case .english: "en"
        case .korean: "ko"
        }
        let detected: String
        if let forced {
            detected = forced
        } else {
            detected = try await whisper.detectLangauge(audioArray: audio).language
        }

        let prompt: String?
        if detected == "en" {
            prompt = options.vocabulary.isEmpty ? nil : options.vocabulary.joined(separator: ", ") + "."
        } else {
            prompt = options.keepEnglishInKorean ? Self.mixedPrompt : nil
        }

        var text = try await run(whisper, audio, prompt: prompt, language: forced)
        if detected != "en", !text.isEmpty, !Self.containsHangul(text) {
            text = try await run(whisper, audio, prompt: nil, language: forced)
        }
        return Result(text: text, language: detected)
    }

    /// Mirrors the whisperkit-cli settings used in the Phase 0 benchmark.
    private func run(_ whisper: WhisperKit, _ audio: [Float], prompt: String?, language: String?) async throws -> String {
        var options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 5,
            topK: 5,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: nil,
            noSpeechThreshold: 0.6,
            chunkingStrategy: .vad
        )
        if let prompt, let tokenizer = whisper.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }
        let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x1100...0x11FF).contains($0.value) }
    }

    enum TranscriberError: LocalizedError {
        case notLoaded
        var errorDescription: String? { "The speech model isn't loaded yet." }
    }
}
