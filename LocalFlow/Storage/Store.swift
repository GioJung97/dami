import Foundation
import GRDB

/// One finished dictation.
struct Dictation: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: Int64?
    var createdAt: Date
    var appName: String?
    var appBundleID: String?
    var language: String
    var audioSeconds: Double
    var latencySeconds: Double
    /// What Whisper produced.
    var rawText: String
    /// What was pasted, after replacements.
    var finalText: String
    /// Short human-readable note about what changed between raw and final.
    var note: String?

    static let databaseTableName = "dictation"

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    var wordCount: Int { finalText.split(whereSeparator: \.isWhitespace).count }

    var languageLabel: String {
        switch language {
        case "en": "EN"
        case "ko": finalText.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil ? "MIXED" : "KO"
        default: language.uppercased()
        }
    }
}

/// A word Whisper should spell your way. English terms are fed to Whisper as a hint.
struct VocabularyTerm: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: Int64?
    var term: String
    var createdAt: Date

    static let databaseTableName = "vocabulary"
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// "When Whisper writes X, write Y instead."
struct Replacement: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: Int64?
    var find: String
    var replace: String
    var uses: Int
    var createdAt: Date

    static let databaseTableName = "replacement"
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// SQLite storage for history and the personal dictionary.
/// Lives at ~/Library/Application Support/LocalFlow/LocalFlow.sqlite.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var dictations: [Dictation] = []
    @Published private(set) var vocabulary: [VocabularyTerm] = []
    @Published private(set) var replacements: [Replacement] = []

    private let db: DatabaseQueue

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalFlow", isDirectory: true)
    }

    static var audioDirectory: URL { supportDirectory.appendingPathComponent("Audio", isDirectory: true) }

    private init() {
        try? FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        db = Self.openDatabase()
        reload()
    }

    private static func openDatabase() -> DatabaseQueue {
        do {
            let queue = try DatabaseQueue(path: supportDirectory.appendingPathComponent("LocalFlow.sqlite").path)
            try migrator.migrate(queue)
            return queue
        } catch {
            // A broken database must not stop dictation. Fall back to memory for this session.
            NSLog("LocalFlow: database unavailable, using in-memory store: \(error.localizedDescription)")
            let queue = try! DatabaseQueue()
            try! migrator.migrate(queue)
            return queue
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "dictation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("appName", .text)
                t.column("appBundleID", .text)
                t.column("language", .text).notNull()
                t.column("audioSeconds", .double).notNull()
                t.column("latencySeconds", .double).notNull()
                t.column("rawText", .text).notNull()
                t.column("finalText", .text).notNull()
                t.column("note", .text)
            }
            try db.create(table: "vocabulary") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("term", .text).notNull().unique(onConflict: .ignore)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "replacement") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("find", .text).notNull().unique(onConflict: .replace)
                t.column("replace", .text).notNull()
                t.column("uses", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            // Starting points from the Phase 0 benchmark. Editable in the Dictionary.
            let now = Date()
            for term in ["Supabase", "Vercel", "Claude Code", "pull request", "commit", "deploy", "refactoring", "LocalFlow"] {
                var row = VocabularyTerm(term: term, createdAt: now)
                try row.insert(db)
            }
            for (find, replace) in [("클라우드 코드", "Claude Code"), ("Cloud Code", "Claude Code"), ("superbase", "Supabase")] {
                var row = Replacement(find: find, replace: replace, uses: 0, createdAt: now)
                try row.insert(db)
            }
        }
        return migrator
    }

    func reload() {
        do {
            try db.read { db in
                dictations = try Dictation.order(Column("createdAt").desc).limit(5000).fetchAll(db)
                vocabulary = try VocabularyTerm.order(Column("createdAt")).fetchAll(db)
                replacements = try Replacement.order(Column("createdAt")).fetchAll(db)
            }
        } catch {
            NSLog("LocalFlow: reload failed: \(error.localizedDescription)")
        }
    }

    // MARK: History

    @discardableResult
    func add(_ dictation: Dictation) -> Dictation {
        var row = dictation
        try? db.write { db in try row.insert(db) }
        reload()
        return row
    }

    func delete(_ dictation: Dictation) {
        guard let id = dictation.id else { return }
        _ = try? db.write { db in try Dictation.deleteOne(db, id: id) }
        try? FileManager.default.removeItem(at: Self.audioURL(for: id))
        reload()
    }

    func deleteAllHistory() {
        _ = try? db.write { db in try Dictation.deleteAll(db) }
        try? FileManager.default.removeItem(at: Self.audioDirectory)
        reload()
    }

    /// Applies the retention setting: 0 = keep forever, -1 = keep nothing, N = keep N days.
    func prune(retentionDays: Int) {
        guard retentionDays != 0 else { return }
        let cutoff = retentionDays < 0 ? Date.distantFuture : Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        _ = try? db.write { db in
            try Dictation.filter(Column("createdAt") < cutoff).deleteAll(db)
        }
        reload()
    }

    static func audioURL(for id: Int64) -> URL {
        audioDirectory.appendingPathComponent("\(id).wav")
    }

    // MARK: Dictionary

    func addTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var row = VocabularyTerm(term: trimmed, createdAt: Date())
        try? db.write { db in try row.insert(db) }
        reload()
    }

    func removeTerm(_ term: VocabularyTerm) {
        guard let id = term.id else { return }
        _ = try? db.write { db in try VocabularyTerm.deleteOne(db, id: id) }
        reload()
    }

    func addReplacement(find: String, replace: String) {
        let find = find.trimmingCharacters(in: .whitespacesAndNewlines)
        let replace = replace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !find.isEmpty, !replace.isEmpty else { return }
        var row = Replacement(find: find, replace: replace, uses: 0, createdAt: Date())
        try? db.write { db in try row.insert(db) }
        reload()
    }

    func removeReplacement(_ replacement: Replacement) {
        guard let id = replacement.id else { return }
        _ = try? db.write { db in try Replacement.deleteOne(db, id: id) }
        reload()
    }

    func recordUses(_ counts: [Int64: Int]) {
        guard !counts.isEmpty else { return }
        try? db.write { db in
            for (id, count) in counts {
                try db.execute(sql: "UPDATE replacement SET uses = uses + ? WHERE id = ?", arguments: [count, id])
            }
        }
        reload()
    }
}

// MARK: - Stats for the Home screen

extension Store {
    struct DayStats {
        var words = 0
        var dictations = 0
        var minutesSaved = 0.0
        var averageLatency: Double?
        var streakDays = 0
    }

    /// Typing speed used to estimate time saved.
    static let typingWordsPerMinute = 40.0

    func todayStats(now: Date = Date()) -> DayStats {
        let calendar = Calendar.current
        let today = dictations.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
        var stats = DayStats()
        stats.dictations = today.count
        stats.words = today.reduce(0) { $0 + $1.wordCount }
        let speakingMinutes = today.reduce(0) { $0 + $1.audioSeconds } / 60
        stats.minutesSaved = max(0, Double(stats.words) / Self.typingWordsPerMinute - speakingMinutes)
        if !today.isEmpty {
            stats.averageLatency = today.reduce(0) { $0 + $1.latencySeconds } / Double(today.count)
        }

        let days = Set(dictations.map { calendar.startOfDay(for: $0.createdAt) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(day) {
            stats.streakDays += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return stats
    }
}
