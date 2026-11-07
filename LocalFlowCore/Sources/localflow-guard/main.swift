import Foundation
import LocalFlowCore

// Runs `SmartGuard` for `bench/smart_eval.py`, so the offline eval judges exactly as the app will.
// Reads JSON lines {"input": "...", "output": "..."} on stdin, writes {"pass": true, "deleted": [{"words": [...], "reason": "..."}]}.
// {"light": "...", "language": "ko"} instead returns {"text": "..."}: Light's output, as `localflow-eval` computes it.
struct Request: Decodable { let input: String?; let output: String?; let light: String?; let language: String? }
struct LightReply: Encodable { let text: String }
struct Reply: Encodable {
    struct Deleted: Encodable { let words: [String]; let reason: String }
    let pass: Bool
    let deleted: [Deleted]
}

// One reply per line, at once: the caller waits for each before sending the next.
setvbuf(stdout, nil, _IOLBF, 0)
let encoder = JSONEncoder()
while let line = readLine() {
    guard let request = try? JSONDecoder().decode(Request.self, from: Data(line.utf8)) else {
        print(#"{"pass":false,"deleted":[],"error":"bad request"}"#)
        continue
    }
    if let light = request.light {
        let language = request.language == "mixed" ? "ko" : request.language ?? "en"
        let text = TextPipeline.process(raw: light, mode: .light, language: language, rules: []).final
        print(String(decoding: try! encoder.encode(LightReply(text: text)), as: UTF8.self))
        continue
    }
    let reply: Reply = switch SmartGuard.check(input: request.input ?? "", output: request.output ?? "") {
    case .pass(let deleted): Reply(pass: true, deleted: deleted.map { .init(words: $0.words, reason: $0.reason.rawValue) })
    case .fail: Reply(pass: false, deleted: [])
    }
    print(String(decoding: try! encoder.encode(reply), as: UTF8.self))
}
