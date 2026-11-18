import CoreML
import Foundation
import WhisperKit

// Usage: lideval <manifest.jsonl> <out.jsonl> [--limit N] [--decode-only]
// --decode-only: skip the 4 s windows and the auto run; only the whole-clip score and the three forced runs (with their stats).
// Manifest lines: {"id", "audio" (path), "l2" (whisper code), "prompt" (that language's mixed prompt)}
// Out lines, one per clip: language scores for the whole clip (as the app does it) and for short windows, and the text from
// each way of running Whisper. Rules are then compared in Python from this file alone (bench/lid_score.py).
// Clips already in the out file are skipped, so a run can be stopped and continued.

struct ManifestLine: Decodable { let id: String; let audio: String; let l2: String; let prompt: String }

struct WindowScore: Encodable {
    let start: Double
    let end: Double
    /// Log-softmax over all of Whisper's language tokens, for English and the second language.
    let en: Float
    let l2: Float
    /// The language Whisper itself would pick among all of them.
    let top: String
}

/// What Whisper says about its own output, for choosing between two runs without the reference.
struct RunStats: Encodable {
    /// Sum and count of log probabilities of the text tokens (no special or timestamp tokens), over all segments.
    let textLogprob: Float
    let textTokens: Int
    /// Worst segment's avgLogprob and compressionRatio, highest temperature used (above 0 means a fallback happened).
    let minAvgLogprob: Float
    let maxCompressionRatio: Float
    let maxTemperature: Float
    let maxNoSpeechProb: Float
    let segments: Int
}

struct Run: Encodable { let text: String; let seconds: Double; let stats: RunStats? }

struct OutLine: Encodable {
    let id: String
    let l2: String
    let audioSeconds: Double
    let whole: WindowScore
    let windows: [WindowScore]
    let forcedEN: Run
    let forcedL2Prompt: Run
    let forcedL2NoPrompt: Run
    let auto: Run?
    let detectSeconds: Double
}

/// Whisper's language tokens (large-v3 has 100).
let languageCodes = ["en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar", "sv", "it", "id", "hi",
    "fi", "vi", "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no", "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy",
    "sk", "te", "fa", "lv", "bn", "sr", "az", "sl", "kn", "et", "mk", "br", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw",
    "gl", "mr", "pa", "si", "km", "sn", "yo", "so", "af", "oc", "ka", "be", "tg", "sd", "gu", "am", "yi", "lo", "uz", "fo", "ht",
    "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl", "mg", "as", "tt", "haw", "ln", "ha", "ba", "jw", "su", "yue"]

/// Short windows: long enough for Whisper to hear a language, short enough that a minority language isn't drowned out.
let windowSeconds = 4.0
let hopSeconds = 2.0

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: lideval <manifest.jsonl> <out.jsonl> [--limit N]"); exit(2) }
let decodeOnly = args.contains("--decode-only")
let limit = args.firstIndex(of: "--limit").flatMap { Int(args[$0 + 1]) } ?? .max

let modelFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Dami/Models/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB")

let whisper = try await WhisperKit(WhisperKitConfig(
    modelFolder: modelFolder.path,
    computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine),
    verbose: false, logLevel: .error, prewarm: true, load: true, download: false
))
guard let tokenizer = whisper.tokenizer else { fatalError("no tokenizer") }
let languageTokens = languageCodes.compactMap { code in tokenizer.convertTokenToId("<|\(code)|>").map { (code, $0) } }

func score(_ audio: [Float], from start: Int, count: Int, l2: String) async throws -> WindowScore {
    let window = whisper.featureExtractor.windowSamples ?? 480_000
    let slice = Array(audio[start..<min(audio.count, start + count)])
    guard let samples = whisper.audioProcessor.padOrTrim(fromArray: slice, startAt: 0, toLength: window),
          let mel = try await whisper.featureExtractor.logMelSpectrogram(fromAudio: samples),
          let encoded = try await whisper.audioEncoder.encodeFeatures(mel) as? MLMultiArray,
          let inputs = try whisper.textDecoder.prepareDecoderInputs(withPrompt: [tokenizer.specialTokens.startOfTranscriptToken])
              as? DecodingInputs
    else { fatalError("detection setup failed") }
    inputs.inputIds[0] = NSNumber(value: tokenizer.specialTokens.startOfTranscriptToken)
    inputs.cacheLength[0] = 0
    let output = try await whisper.textDecoder.predictLogits(TextDecoderMLMultiArrayInputType(
        inputIds: inputs.inputIds, cacheLength: inputs.cacheLength, keyCache: inputs.keyCache, valueCache: inputs.valueCache,
        kvCacheUpdateMask: inputs.kvCacheUpdateMask, encoderOutputEmbeds: encoded, decoderKeyPaddingMask: inputs.decoderKeyPaddingMask
    )) as? TextDecoderMLMultiArrayOutputType
    guard let logits = output?.logits else { fatalError("no logits") }
    let values = languageTokens.map { ($0.0, logits[[0, 0, NSNumber(value: $0.1)]].floatValue) }
    let maxValue = values.map(\.1).max()!
    let logSum = log(values.reduce(Float(0)) { $0 + exp($1.1 - maxValue) }) + maxValue
    let lookup = Dictionary(uniqueKeysWithValues: values)
    return WindowScore(
        start: Double(start) / 16_000, end: Double(start + slice.count) / 16_000,
        en: lookup["en"]! - logSum, l2: lookup[l2]! - logSum,
        top: values.max { $0.1 < $1.1 }!.0
    )
}

/// The app's decoding settings (Transcriber.run), so the text here is what the app would paste.
func transcribe(_ audio: [Float], language: String?, prompt: String?) async throws -> Run {
    let started = Date()
    var options = DecodingOptions(
        task: .transcribe, language: language, temperature: 0, temperatureIncrementOnFallback: 0.2, temperatureFallbackCount: 5,
        topK: 5, usePrefillPrompt: language != nil, detectLanguage: language == nil, compressionRatioThreshold: 2.4,
        logProbThreshold: -1.0, firstTokenLogProbThreshold: nil, noSpeechThreshold: 0.6, chunkingStrategy: .vad
    )
    if let prompt, !prompt.isEmpty {
        options.promptTokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        options.usePrefillPrompt = true
    }
    let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
    let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let segments = results.flatMap(\.segments)
    var sum: Float = 0, count = 0
    for segment in segments {
        for (token, probs) in zip(segment.tokens, segment.tokenLogProbs) where token < tokenizer.specialTokens.specialTokenBegin {
            if let p = probs[token] { sum += p; count += 1 }
        }
    }
    let stats = RunStats(
        textLogprob: sum, textTokens: count,
        minAvgLogprob: segments.map(\.avgLogprob).min() ?? 0, maxCompressionRatio: segments.map(\.compressionRatio).max() ?? 0,
        maxTemperature: segments.map(\.temperature).max() ?? 0, maxNoSpeechProb: segments.map(\.noSpeechProb).max() ?? 0,
        segments: segments.count
    )
    return Run(text: text, seconds: Date().timeIntervalSince(started), stats: stats)
}

let outURL = URL(fileURLWithPath: args[2])
var done = Set<String>()
if let existing = try? String(contentsOf: outURL, encoding: .utf8) {
    for line in existing.split(separator: "\n") {
        if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = object["id"] as? String {
            done.insert(id)
        }
    }
}
if !FileManager.default.fileExists(atPath: outURL.path) { FileManager.default.createFile(atPath: outURL.path, contents: nil) }
let out = try FileHandle(forWritingTo: outURL)
out.seekToEndOfFile()
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

let manifest = try String(contentsOfFile: args[1], encoding: .utf8).split(separator: "\n")
    .map { try JSONDecoder().decode(ManifestLine.self, from: Data($0.utf8)) }
var processed = 0
for clip in manifest where !done.contains(clip.id) {
    guard processed < limit else { break }
    let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: clip.audio)
    let detectStarted = Date()
    let whole = try await score(audio, from: 0, count: audio.count, l2: clip.l2)
    let detectSeconds = Date().timeIntervalSince(detectStarted)
    var windows: [WindowScore] = []
    let size = Int(windowSeconds * 16_000), hop = Int(hopSeconds * 16_000)
    if audio.count > size && !decodeOnly {
        var start = 0
        while start < audio.count {
            windows.append(try await score(audio, from: start, count: size, l2: clip.l2))
            if start + size >= audio.count { break }
            start += hop
        }
    }
    let line = OutLine(
        id: clip.id, l2: clip.l2, audioSeconds: Double(audio.count) / 16_000, whole: whole, windows: windows,
        forcedEN: try await transcribe(audio, language: "en", prompt: nil),
        forcedL2Prompt: try await transcribe(audio, language: clip.l2, prompt: clip.prompt),
        forcedL2NoPrompt: try await transcribe(audio, language: clip.l2, prompt: nil),
        auto: decodeOnly ? nil : try await transcribe(audio, language: nil, prompt: nil),
        detectSeconds: detectSeconds
    )
    out.write(try encoder.encode(line) + Data("\n".utf8))
    processed += 1
    if processed % 25 == 0 { print("\(processed) clips"); fflush(stdout) }
}
print("done: \(processed) new clips")
