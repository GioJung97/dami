import CoreML
import Foundation
import LocalFlowCore
import WhisperKit

/// On-device speech-to-text with WhisperKit, using the language-adaptive prompting chosen in
/// Phase 0 (PLAN §5):
/// 1. Detect the language among the user's languages (English + at most one other), unless the
///    user fixed it.
/// 2. English → prompt with the vocabulary list. Other language (incl. mixed) → short mixed sample only.
/// 3. If the other language was detected but the result isn't in its script, Whisper translated:
///    re-run without a prompt. (Only possible for languages with their own script.)
actor Transcriber {
    static let modelName = "large-v3-v20240930_turbo_632MB"
    static let modelDisplayName = "Whisper large-v3 turbo"
    static let modelSizeMB = 632

    struct Options: Sendable {
        /// The language spoken next to English, or nil for English only.
        var secondLanguage: SpokenLanguage?
        /// Fixed language code, or nil to detect between English and `secondLanguage`.
        var forcedLanguage: String?
        var keepEnglishTerms: Bool
        /// English terms from the Dictionary, used as the prompt for English dictations.
        var vocabulary: [String]
    }

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

        let language: String
        if let forced = options.forcedLanguage {
            language = forced
        } else if let second = options.secondLanguage {
            language = try await detectLanguage(whisper, audio, among: ["en", second.code])
        } else {
            language = "en"
        }

        let second = language == "en" ? nil : options.secondLanguage
        let prompt: String?
        if let second {
            prompt = options.keepEnglishTerms ? second.mixedPrompt : nil
        } else {
            prompt = options.vocabulary.isEmpty ? nil : options.vocabulary.joined(separator: ", ") + "."
        }

        var text = try await run(whisper, audio, prompt: prompt, language: language)
        if let script = second?.script, prompt != nil, !text.isEmpty, !script.matches(text) {
            text = try await run(whisper, audio, prompt: nil, language: language)
        }
        return Result(text: text, language: language)
    }

    /// Whisper's own detection picks from all 99 languages, so Korean is sometimes heard as Japanese.
    /// This runs the same single decoder step but only compares the user's languages.
    private func detectLanguage(_ whisper: WhisperKit, _ audio: [Float], among codes: [String]) async throws -> String {
        guard let tokenizer = whisper.tokenizer else { throw TranscriberError.notLoaded }
        let window = whisper.featureExtractor.windowSamples ?? 480_000
        guard let samples = whisper.audioProcessor.padOrTrim(fromArray: audio, startAt: 0, toLength: window),
              let mel = try await whisper.featureExtractor.logMelSpectrogram(fromAudio: samples),
              let encoded = try await whisper.audioEncoder.encodeFeatures(mel) as? MLMultiArray,
              let inputs = try whisper.textDecoder.prepareDecoderInputs(
                  withPrompt: [tokenizer.specialTokens.startOfTranscriptToken]
              ) as? DecodingInputs
        else { throw TranscriberError.detectionFailed }

        inputs.inputIds[0] = NSNumber(value: tokenizer.specialTokens.startOfTranscriptToken)
        inputs.cacheLength[0] = 0
        let output = try await whisper.textDecoder.predictLogits(TextDecoderMLMultiArrayInputType(
            inputIds: inputs.inputIds,
            cacheLength: inputs.cacheLength,
            keyCache: inputs.keyCache,
            valueCache: inputs.valueCache,
            kvCacheUpdateMask: inputs.kvCacheUpdateMask,
            encoderOutputEmbeds: encoded,
            decoderKeyPaddingMask: inputs.decoderKeyPaddingMask
        )) as? TextDecoderMLMultiArrayOutputType
        guard let logits = output?.logits else { throw TranscriberError.detectionFailed }

        let scored = codes.compactMap { code -> (String, Float)? in
            guard let token = tokenizer.convertTokenToId("<|\(code)|>") else { return nil }
            return (code, logits[[0, 0, NSNumber(value: token)]].floatValue)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else { throw TranscriberError.detectionFailed }
        return best.0
    }

    /// Mirrors the whisperkit-cli settings used in the Phase 0 benchmark.
    private func run(_ whisper: WhisperKit, _ audio: [Float], prompt: String?, language: String) async throws -> String {
        var options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 5,
            topK: 5,
            usePrefillPrompt: true,
            detectLanguage: false,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: nil,
            noSpeechThreshold: 0.6,
            chunkingStrategy: .vad
        )
        if let prompt, let tokenizer = whisper.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum TranscriberError: LocalizedError {
        case notLoaded, detectionFailed
        var errorDescription: String? {
            switch self {
            case .notLoaded: "The speech model isn't loaded yet."
            case .detectionFailed: "Couldn't tell which language was spoken."
            }
        }
    }
}
