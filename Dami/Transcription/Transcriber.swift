import CoreML
import Foundation
import DamiCore
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
/// 4. When detection is unsure (v1.1), transcribe as both and keep the text Whisper is more sure of.
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
        /// A retry of a dropped dictation: no prompt, and silence around the speech from the start (v0.3.1 M4). The language is
        /// forced to the other one by the caller.
        var isDropRetry = false
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
        var timings = Timings()
    }

    /// Seconds per stage, numbers only, for the `latency` log (v0.4 M1).
    struct Timings: Sendable {
        var detect: Double = 0
        var transcribe: Double = 0
        /// Whisper runs, including retries.
        var runs = 0
        /// Windows whose encoder output was reused instead of encoded again (v1.0 M2).
        var reused = 0
        /// Detection was unsure, so both languages were transcribed (v1.1), and whether the other one was kept.
        var compared = false
        var switched = false
    }

    private var whisper: WhisperKit?
    private var loading: Task<Void, Error>?
    private let log = Logger(subsystem: "io.github.giojung97.dami", category: "transcriber")

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dami/Models", isDirectory: true)
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
            whisper.audioEncoder = ReusingAudioEncoder(base: whisper.audioEncoder)
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
            monitor.start(queue: DispatchQueue(label: "io.github.giojung97.dami.pathcheck"))
        }
    }

    func transcribe(_ audio: [Float], options: Options) async throws -> Result {
        guard let whisper else { throw TranscriberError.notLoaded }
        let encoder = whisper.audioEncoder as? ReusingAudioEncoder
        encoder?.clear()
        defer { encoder?.clear() }

        // Nil leaves it to Whisper's own detection, without a prompt.
        var timings = Timings()
        let detectStarted = Date()
        var language: String?
        var unsure = false
        if let forced = options.forcedLanguage {
            language = forced
        } else if let second = options.secondLanguage {
            do {
                let detection = try await detectLanguage(whisper, audio, among: ["en", second.code])
                language = detection.code
                unsure = Self.unsureMargins.contains(detection.margin)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                log.error("Language detection failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            language = "en"
        }

        timings.detect = Date().timeIntervalSince(detectStarted)
        let transcribeStarted = Date()

        if options.isDropRetry {
            let padding = [Float](repeating: 0, count: Self.paddingSamples)
            var retry = try await self.run(whisper, padding + audio + padding, prompt: nil, language: language, wordTimestamps: options.wordTimestamps)
            let offset = Float(Self.paddingSamples) / Float(AudioRecorder.sampleRate)
            retry.words = retry.words.map { Word(word: $0.word, start: max(0, $0.start - offset), end: max(0, $0.end - offset), probability: $0.probability) }
            timings.runs = 1
            timings.transcribe = Date().timeIntervalSince(transcribeStarted)
            timings.reused = encoder?.reused ?? 0
            return Result(text: retry.text, language: language ?? retry.language ?? "en", prompt: nil, promptVocabulary: [], words: retry.words, timings: timings)
        }

        var chosen = try await decode(whisper, audio, language: language, options: options)
        timings.runs = chosen.runs
        // Unsure: the other language too, and keep the more confident text. Measured on public code-switching data in 9
        // languages, tuned on 4 and checked on the other 5 (bench/lid_select.py, 2026-11-15): severe failures 3.4% → 1.6% on the
        // tuning languages and 4.1% → 3.4% on the others, none worse. Clear English or clear second language never get here.
        // The other run gets no temperature fallback: when it would need one (about 1 in 20 there) it took about 4 s instead of
        // 0.8 s and was never the better text, so it is dropped instead.
        if unsure, let first = language, let second = options.secondLanguage {
            let other = try await decode(whisper, audio, language: first == "en" ? second.code : "en", options: options, fallback: false)
            timings.runs += other.runs
            timings.compared = true
            if other.run.passedChecks, other.run.confidence > chosen.run.confidence {
                chosen = other
                language = other.language
                timings.switched = true
            }
        }
        var run = chosen.run
        var prompt = chosen.prompt
        let vocabularyInPrompt = chosen.vocabulary
        // A very short clip with the prompt can come back empty: Whisper ends at once. Retry once without it, with a little silence
        // around the speech, which brought all five empty clips back in testing (2026-11-05).
        if run.text.isEmpty, prompt != nil || audio.count < Self.shortClipSamples {
            let padding = [Float](repeating: 0, count: Self.paddingSamples)
            var retry = try await self.run(whisper, padding + audio + padding, prompt: nil, language: language, wordTimestamps: options.wordTimestamps)
            let offset = Float(Self.paddingSamples) / Float(AudioRecorder.sampleRate)
            retry.words = retry.words.map { Word(word: $0.word, start: max(0, $0.start - offset), end: max(0, $0.end - offset), probability: $0.probability) }
            run = retry
            prompt = nil
            timings.runs += 1
        }
        timings.transcribe = Date().timeIntervalSince(transcribeStarted)
        timings.reused = encoder?.reused ?? 0
        return Result(
            text: run.text,
            language: language ?? run.language ?? "en",
            prompt: prompt,
            promptVocabulary: prompt != nil && language == "en" ? vocabularyInPrompt : [],
            words: run.words,
            timings: timings
        )
    }

    /// Whole terms that fit in the prompt, newest first. Empty until the model is loaded.
    func fittingVocabulary(_ terms: [String]) -> [String] {
        guard let tokenizer = whisper?.tokenizer else { return [] }
        return VocabularyPrompt.fitting(terms) { text in
            tokenizer.encode(text: text).filter { $0 < tokenizer.specialTokens.specialTokenBegin }.count
        }
    }

    var isLoaded: Bool { whisper != nil }

    /// Half a second of silence on each side for the empty-result retry.
    private static let paddingSamples = 8_000
    /// Under this, a retry also runs when there was no prompt, since short clips are the ones that come back empty.
    private static let shortClipSamples = 48_000

    /// Detection between English and the second language, nearly even: here the higher score is often the wrong one, and the
    /// two transcriptions are compared instead. Margin is English minus the second language, in log probability. Chosen on
    /// public data (bench/lid_select.py, 2026-11-15); clear cases (about 4 of 5 clips there, more in everyday use) skip it.
    static let unsureMargins: ClosedRange<Float> = -3...7

    /// One way of transcribing: the language's prompt, and for the second language the check that Whisper didn't translate.
    private func decode(_ whisper: WhisperKit, _ audio: [Float], language: String?, options: Options, fallback: Bool = true) async throws
        -> (run: Decoded, language: String?, prompt: String?, vocabulary: [String], runs: Int) {
        let second = language == "en" ? nil : options.secondLanguage
        var prompt: String?
        var vocabulary: [String] = []
        if language == nil {
            prompt = nil
        } else if let second {
            prompt = options.keepEnglishTerms ? second.mixedPrompt : nil
        } else {
            let terms = fittingVocabulary(options.vocabulary)
            prompt = terms.isEmpty ? nil : VocabularyPrompt.text(terms)
            vocabulary = terms
        }
        var run = try await self.run(whisper, audio, prompt: prompt, language: language, wordTimestamps: options.wordTimestamps, fallback: fallback)
        var runs = 1
        if let script = second?.script, prompt != nil, !run.text.isEmpty, !script.matches(run.text) {
            run = try await self.run(whisper, audio, prompt: nil, language: language, wordTimestamps: options.wordTimestamps, fallback: fallback)
            prompt = nil
            runs += 1
        }
        return (run, language, prompt, vocabulary, runs)
    }

    /// Whisper's own detection picks from all 99 languages, so Korean is sometimes heard as Japanese.
    /// This runs the same single decoder step but only compares the user's languages. The margin is the first code's score
    /// minus the best other one's.
    private func detectLanguage(_ whisper: WhisperKit, _ audio: [Float], among codes: [String]) async throws -> (code: String, margin: Float) {
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
        guard let best = scored.max(by: { $0.1 < $1.1 }), let first = scored.first else { throw TranscriberError.detectionFailed }
        let margin = first.1 - (scored.dropFirst().map(\.1).max() ?? first.1)
        return (best.0, margin)
    }

    /// A run's text and how sure Whisper was of it.
    struct Decoded {
        var text: String
        var language: String?
        var words: [Word]
        /// Mean log probability of the text tokens (no special or timestamp tokens). Per token, so a script that needs more
        /// tokens isn't penalised for length. -infinity when there's no text, so any text wins over none.
        var confidence: Float
        /// Whisper's own quality check passed with no retry at a higher temperature: not too repetitive, not too unsure.
        var passedChecks: Bool
    }

    /// Mirrors the whisperkit-cli settings used in the Phase 0 benchmark.
    /// `fallback: false` keeps the first try even when it fails Whisper's quality check, and says so in `passedChecks`.
    private func run(_ whisper: WhisperKit, _ audio: [Float], prompt: String?, language: String?, wordTimestamps: Bool,
                     fallback: Bool = true) async throws -> Decoded {
        var options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: fallback ? 5 : 0,
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
        var sum: Float = 0
        var count = 0
        if let textEnd = whisper.tokenizer?.specialTokens.specialTokenBegin {
            for segment in results.flatMap(\.segments) {
                for (token, probabilities) in zip(segment.tokens, segment.tokenLogProbs) where token < textEnd {
                    if let p = probabilities[token] { sum += p; count += 1 }
                }
            }
        }
        // The same test WhisperKit uses to decide on a fallback (DecodingFallback), with this function's thresholds. A segment
        // judged silent doesn't count against it.
        let passed = results.flatMap(\.segments).allSatisfy { segment in
            segment.noSpeechProb > (options.noSpeechThreshold ?? 1)
                || (segment.compressionRatio <= (options.compressionRatioThreshold ?? .infinity)
                    && segment.avgLogprob >= (options.logProbThreshold ?? -.infinity))
        }
        return Decoded(text: text, language: results.first?.language, words: words,
                       confidence: count > 0 ? sum / Float(count) : -.infinity, passedChecks: passed)
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

/// Remembers the encoder's output for the last window it encoded, so the same audio isn't encoded twice: once to tell the two
/// languages apart and again by WhisperKit for the first window, or again for a run without the prompt (v1.0 M2, about 0.4 s
/// each). A window counts as the same only if its mel features are equal byte for byte. Cleared around every dictation.
final class ReusingAudioEncoder: AudioEncoding {
    private let base: any AudioEncoding
    private var lastFeatures: Data?
    private var lastOutput: (any AudioEncoderOutputType)?
    private(set) var reused = 0

    init(base: any AudioEncoding) {
        self.base = base
    }

    var embedSize: Int? { base.embedSize }

    func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
        let key = (features as? MLMultiArray).map(Self.bytes)
        if let key, key == lastFeatures, let lastOutput {
            reused += 1
            return lastOutput
        }
        let output = try await base.encodeFeatures(features)
        lastFeatures = key
        lastOutput = output
        return output
    }

    func clear() {
        lastFeatures = nil
        lastOutput = nil
        reused = 0
    }

    private static func bytes(_ array: MLMultiArray) -> Data {
        array.withUnsafeBytes { Data($0) }
    }
}
