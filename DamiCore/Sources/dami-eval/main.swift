import Foundation
import DamiCore

// Usage: dami-eval [cases.tsv] [results.md]
// Exits non-zero if a must_keep case changed.
let arguments = CommandLine.arguments
let casesPath = arguments.count > 1 ? arguments[1] : "bench/cleanup_cases.tsv"
let resultsPath = arguments.count > 2 ? arguments[2] : "bench/cleanup_results.md"

do {
    let results = CleanupEval.run(CleanupEval.parse(try String(contentsOfFile: casesPath, encoding: .utf8)))
    try CleanupEval.report(results).write(toFile: resultsPath, atomically: true, encoding: .utf8)
    let changed = results.filter { $0.testCase.category == "must_keep" && !$0.passed }
    print("\(results.count) cases, \(changed.count) must_keep changed. Wrote \(resultsPath)")
    exit(changed.isEmpty ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("dami-eval: \(error.localizedDescription)\n".utf8))
    exit(2)
}
