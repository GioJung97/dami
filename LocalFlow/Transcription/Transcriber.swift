import CoreML
import Foundation
import LocalFlowCore
import Network
import WhisperKit
import os

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
        /// Measure each word's timing and confidence, for `Result.words`. Measured cost: at most
        /// 23 ms on 3–29 s of audio. v0.3 can use it to tell mishearing from a change of mind.
        var wordTimestamps = false
    }

    /// One word with when it was said and how sure Whisper was.
    struct Word: Codable, Sendable {
        let word: String
        let start: Float
        let end: Float
        let probability: Float
    }

    struct Result: Sendable {
        let text: String
        let language: String
        /// The prompt behind `text`, if any. Whisper can repeat it on noise.
        let prompt: String?
        /// The vocabulary list, if that's what the prompt was.
        let promptVocabulary: [String]
        var words: [Word] = []
    }

    private var whisper: WhisperKit?
    private var loading: Task<Void, Error>?
    private let log = Logger(subsystem: "com.localflow.app", category: "transcriber")

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalFlow/Models", isDirectory: true)
    }

    static var modelFolder: URL {
        modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)", isDirectory: true)
    }

    static var isModelDownloaded: Bool {
        ModelFiles.isComplete { FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent($0).path) }
    }

    /// Free space to insist on before downloading: the model plus room for temporary files.
    private static let requiredFreeBytes: Int64 = 1_000_000_000

    /// Downloads the model if needed (reporting 0…1 progress), loads it, and warms it up so the
    /// first real dictation isn't slow.
    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard whisper == nil else { return }
        if let loading { return try await loading.value }
        let task = Task { try await loadModel(progress: progress) }
        loading = task
        defer { loading = nil }
        try await task.value
    }

    /// Deletes the model, for when its files turned out to be bad. `load` then downloads it again.
    func deleteModel() {
        guard whisper == nil else { return }
        try? FileManager.default.removeItem(at: Self.modelFolder)
    }

    /// Waits for a load in progress, so a dictation made right after launch isn't lost.
    func waitUntilReady() async throws {
        if whisper == nil, let loading { try await loading.value }
        guard whisper != nil else { throw TranscriberError.notLoaded }
    }

    private func loadModel(progress: @escaping @Sendable (Double) -> Void) async throws {
        let folder: URL
        if Self.isModelDownloaded {
            folder = Self.modelFolder
        } else {
            folder = try await downloadModel(progress: progress)
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
        do {
            let whisper = try await WhisperKit(config)
            _ = try? await whisper.transcribe(audioArray: [Float](repeating: 0, count: 16_000))
            self.whisper = whisper
        } catch {
            log.error("Model load failed: \(error.localizedDescription, privacy: .public)")
            throw ModelProblem.loadFailed
        }
    }

    private func downloadModel(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        do {
            try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
            let free = try Self.modelsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
            if let free, free < Self.requiredFreeBytes { throw ModelProblem.notEnoughSpace }
            return try await WhisperKit.download(variant: Self.modelName, downloadBase: Self.modelsDirectory) { p in
                progress(p.fractionCompleted)
            }
        } catch let problem as ModelProblem {
            throw problem
        } catch {
            log.error("Model download failed: \(error.localizedDescription, privacy: .public)")
            throw await Self.isOnline() ? ModelProblem.downloadFailed : ModelProblem.noInternet
        }
    }

    /// The download library rewraps network errors, so ask the system directly.
    private static func isOnline() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "com.localflow.pathcheck"))
        }
    }

    func transcribe(_ audio: [Float], options: Options) async throws -> Result {
        guard let whisper else { throw TranscriberError.notLoaded }

        // Nil leaves it to Whisper's own detection, without a prompt.
        var language: String?
        if let forced = options.forcedLanguage {
            language = forced
        } else if let second = options.secondLanguage {
            do {
                language = try await detectLanguage(whisper, audio, among: ["en", second.code])
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                log.error("Language detection failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            language = "en"
        }

        let second = language == "en" ? nil : options.secondLanguage
        var prompt: String?
        if language == nil {
            prompt = nil
        } else if let second {
            prompt = options.keepEnglishTerms ? second.mixedPrompt : nil
        } else {
            prompt = options.vocabulary.isEmpty ? nil : options.vocabulary.joined(separator: ", ") + "."
        }

        var run = try await run(whisper, audio, prompt: prompt, language: language, wordTimestamps: options.wordTimestamps)
        if let script = second?.script, prompt != nil, !run.text.isEmpty, !script.matches(run.text) {
            run = try await self.run(whisper, audio, prompt: nil, language: language, wordTimestamps: options.wordTimestamps)
            prompt = nil
        }
        return Result(
            text: run.text,
            language: language ?? run.language ?? "en",
            prompt: prompt,
            promptVocabulary: prompt != nil && language == "en" ? options.vocabulary : [],
            words: run.words
        )
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
    private func run(_ whisper: WhisperKit, _ audio: [Float], prompt: String?, language: String?, wordTimestamps: Bool) async throws -> (text: String, language: String?, words: [Word]) {
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
        options.wordTimestamps = wordTimestamps
        if let prompt, let tokenizer = whisper.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }
        let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let words = results.flatMap(\.allWords).map { Word(word: $0.word, start: $0.start, end: $0.end, probability: $0.probability) }
        return (text, results.first?.language, words)
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

/// Why the speech model isn't available.
enum ModelProblem: Error, Equatable, Sendable {
    case noInternet, notEnoughSpace, downloadFailed, loadFailed

    var message: String {
        switch self {
        case .noInternet: "No internet connection"
        case .notEnoughSpace: "Not enough disk space"
        case .downloadFailed: "The download didn't finish"
        case .loadFailed: "Speech model couldn't load"
        }
    }

    var advice: String {
        switch self {
        case .noInternet: "Connect to the internet, then try again. This download happens only once."
        case .notEnoughSpace: "The download needs about 1 GB free. Free up some space, then try again."
        case .downloadFailed: "Try again. It picks up what it can."
        case .loadFailed: "The model files may be damaged. Download them again to replace them."
        }
    }

    /// The files are there but bad, so trying again means replacing them.
    var needsRedownload: Bool { self == .loadFailed }
    var actionTitle: String { needsRedownload ? "Re-download" : "Retry" }
}
