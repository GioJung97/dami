import Foundation
import GRDB
import LocalFlowCore

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

    // Recorded since v0.2, null on older rows. None of this can be recovered later.
    /// `CleanupMode` raw value.
    var mode: String? = nil
    /// Text after the cleanup rules, in Light mode.
    var rulesText: String? = nil
    /// JSON array of `CleanupRules.Rule` ids that changed something.
    var rulesApplied: String? = nil
    /// How the text reached the app, e.g. "pasted" or "copied.passwordField".
    var insertOutcome: String? = nil
    var modelName: String? = nil
    var pipelineVersion: String? = nil
    /// The microphone's connection, e.g. "builtIn" or "bluetooth".
    var inputTransport: String? = nil
    /// JSON array of words with timing and confidence, if measured.
    var wordsJSON: String? = nil

    static let databaseTableName = "dictation"

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    var wordCount: Int { finalText.split(whereSeparator: \.isWhitespace).count }

    /// EN, the other language's code (e.g. KO), or MIXED when a dictation in a non-Latin-script
    /// language also has English words. Mixing can't be told apart for Latin-script languages.
    var languageLabel: String {
        guard language != "en" else { return "EN" }
        let hasScript = SpokenLanguage.find(language)?.script != nil
        if hasScript, finalText.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil { return "MIXED" }
        return language.uppercased()
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

    var rule: ReplacementRule { ReplacementRule(id: id, find: find, replace: replace) }
}

/// SQLite storage for history and the personal dictionary.
/// Lives at ~/Library/Application Support/LocalFlow/LocalFlow.sqlite.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var dictations: [Dictation] = []
    @Published private(set) var vocabulary: [VocabularyTerm] = []
    @Published private(set) var replacements: [Replacement] = []

    /// Dictations kept in memory, newest first, for the Home screen and the menu. History queries the database.
    static let recentLimit = 50

    private let db: DatabaseQueue
    private let directory: URL
    /// The database couldn't open. Everything on disk looks orphaned then, so nothing there gets deleted.
    private let isInMemoryFallback: Bool
    private var cachedStats: (day: Date, revision: Int, stats: DayStats)?

    /// Bumped whenever dictations change, so History can query again.
    @Published private(set) var revision = 0

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalFlow", isDirectory: true)
    }

    var audioDirectory: URL { directory.appendingPathComponent("Audio", isDirectory: true) }

    /// - Parameter directory: Where to keep everything. Tests use a scratch folder, never the real one.
    init(directory: URL? = nil) {
        let directory = directory ?? Self.supportDirectory
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        (db, isInMemoryFallback) = Self.openDatabase(in: directory)
        reloadDictionary()
        reloadRecent()
    }

    private static func openDatabase(in directory: URL) -> (DatabaseQueue, isInMemoryFallback: Bool) {
        do {
            let queue = try DatabaseQueue(path: directory.appendingPathComponent("LocalFlow.sqlite").path)
            try migrator.migrate(queue)
            return (queue, false)
        } catch {
            // A broken database must not stop dictation. Fall back to memory for this session.
            NSLog("LocalFlow: database unavailable, using in-memory store: \(error.localizedDescription)")
            let queue = try! DatabaseQueue()
            try! migrator.migrate(queue)
            return (queue, true)
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
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "dictation") { t in
                t.add(column: "mode", .text)
                t.add(column: "rulesText", .text)
                t.add(column: "rulesApplied", .text)
                t.add(column: "insertOutcome", .text)
                t.add(column: "modelName", .text)
                t.add(column: "pipelineVersion", .text)
                t.add(column: "inputTransport", .text)
                t.add(column: "wordsJSON", .text)
            }
        }
        return migrator
    }

    private func reloadDictionary() {
        do {
            try db.read { db in
                vocabulary = try VocabularyTerm.order(Column("createdAt")).fetchAll(db)
                replacements = try Replacement.order(Column("createdAt")).fetchAll(db)
            }
        } catch {
            NSLog("LocalFlow: reload failed: \(error.localizedDescription)")
        }
    }

    private func reloadRecent() {
        do {
            dictations = try db.read { try Dictation.order(Column("createdAt").desc).limit(Self.recentLimit).fetchAll($0) }
        } catch {
            NSLog("LocalFlow: reload failed: \(error.localizedDescription)")
        }
        revision += 1
    }

    // MARK: History

    @discardableResult
    func add(_ dictation: Dictation) -> Dictation {
        var row = dictation
        try? db.write { db in try row.insert(db) }
        dictations = Array(([row] + dictations).prefix(Self.recentLimit))
        revision += 1
        return row
    }

    func delete(_ dictation: Dictation) {
        guard let id = dictation.id else { return }
        _ = try? db.write { db in try Dictation.deleteOne(db, id: id) }
        try? FileManager.default.removeItem(at: audioURL(for: id))
        // The window may have to reach further back now.
        reloadRecent()
    }

    func deleteAllHistory() {
        _ = try? db.write { db in try Dictation.deleteAll(db) }
        try? FileManager.default.removeItem(at: audioDirectory)
        reloadRecent()
    }

    /// Applies the retention settings. Text: 0 = keep forever, -1 = keep nothing, N = keep N days.
    /// Audio follows its own number of days and goes when its row goes. Files without a row are removed.
    func prune(retentionDays: Int, audioRetentionDays: Int, now: Date = Date()) {
        let textCutoff: Date? = switch retentionDays {
        case 0: nil
        case let days where days < 0: .distantFuture
        default: now.addingTimeInterval(-Double(retentionDays) * 86_400)
        }
        if let textCutoff {
            _ = try? db.write { db in
                try Dictation.filter(Column("createdAt") < textCutoff).deleteAll(db)
            }
        }
        pruneAudio(audioCutoff: now.addingTimeInterval(-Double(audioRetentionDays) * 86_400))
        reloadRecent()
    }

    private func pruneAudio(audioCutoff: Date) {
        guard !isInMemoryFallback else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)) ?? []
        let saved = files.filter { $0.pathExtension == "wav" }
        guard !saved.isEmpty else { return }
        // A failed read must not look like "no rows", which would delete every file.
        guard let rows = try? db.read({ db in
            try Row.fetchAll(db, sql: "SELECT id, createdAt FROM dictation").reduce(into: [Int64: Date]()) { result, row in
                result[row["id"]] = row["createdAt"]
            }
        }) else { return }
        for file in saved {
            guard let id = Int64(file.deletingPathExtension().lastPathComponent) else { continue }
            if let createdAt = rows[id], createdAt >= audioCutoff { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    func audioURL(for id: Int64) -> URL {
        audioDirectory.appendingPathComponent("\(id).wav")
    }

    /// Space taken by saved recordings.
    func audioBytesUsed() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // MARK: History queries

    enum LanguageFilter: Equatable {
        case all
        case english
        /// One language. `excludingMixed` leaves out dictations that also contain English.
        case language(String, excludingMixed: Bool)
        case mixed(String)
    }

    struct HistoryQuery: Equatable {
        var search = ""
        var language = LanguageFilter.all
    }

    /// Reaches everything stored, newest first. Mirrors `Dictation.languageLabel` in SQL.
    func history(_ query: HistoryQuery, limit: Int, offset: Int = 0) -> [Dictation] {
        var clauses: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        let hasEnglish = "finalText GLOB '*[A-Za-z][A-Za-z]*'"
        switch query.language {
        case .all:
            break
        case .english:
            clauses.append("language = 'en'")
        case .language(let code, let excludingMixed):
            clauses.append("language = ?" + (excludingMixed ? " AND NOT \(hasEnglish)" : ""))
            arguments.append(code)
        case .mixed(let code):
            clauses.append("language = ? AND \(hasEnglish)")
            arguments.append(code)
        }
        if !query.search.isEmpty {
            let pattern = "%" + Self.escapedForLike(query.search) + "%"
            clauses.append(#"(finalText LIKE ? ESCAPE '\' OR rawText LIKE ? ESCAPE '\')"#)
            arguments += [pattern, pattern]
        }
        let filter = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = "SELECT * FROM dictation \(filter) ORDER BY createdAt DESC LIMIT ? OFFSET ?"
        arguments += [limit, offset]
        return (try? db.read { try Dictation.fetchAll($0, sql: sql, arguments: StatementArguments(arguments)) }) ?? []
    }

    static func escapedForLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: Dictionary

    func addTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var row = VocabularyTerm(term: trimmed, createdAt: Date())
        try? db.write { db in try row.insert(db) }
        reloadDictionary()
    }

    func removeTerm(_ term: VocabularyTerm) {
        guard let id = term.id else { return }
        _ = try? db.write { db in try VocabularyTerm.deleteOne(db, id: id) }
        reloadDictionary()
    }

    func addReplacement(find: String, replace: String) {
        let find = find.trimmingCharacters(in: .whitespacesAndNewlines)
        let replace = replace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !find.isEmpty, !replace.isEmpty else { return }
        var row = Replacement(find: find, replace: replace, uses: 0, createdAt: Date())
        try? db.write { db in try row.insert(db) }
        reloadDictionary()
    }

    func removeReplacement(_ replacement: Replacement) {
        guard let id = replacement.id else { return }
        _ = try? db.write { db in try Replacement.deleteOne(db, id: id) }
        reloadDictionary()
    }

    func recordUses(_ counts: [Int64: Int]) {
        guard !counts.isEmpty else { return }
        try? db.write { db in
            for (id, count) in counts {
                try db.execute(sql: "UPDATE replacement SET uses = uses + ? WHERE id = ?", arguments: [count, id])
            }
        }
        reloadDictionary()
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

    /// Cached until dictations change or the day does, since the Home screen asks on every render.
    func todayStats(now: Date = Date()) -> DayStats {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        if let cachedStats, cachedStats.day == day, cachedStats.revision == revision { return cachedStats.stats }
        let stats = computeStats(day: day, calendar: calendar)
        cachedStats = (day, revision, stats)
        return stats
    }

    private func computeStats(day: Date, calendar: Calendar) -> DayStats {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let today = (try? db.read { db in
            try Dictation.filter(Column("createdAt") >= day && Column("createdAt") < nextDay).fetchAll(db)
        }) ?? []
        var stats = DayStats()
        stats.dictations = today.count
        stats.words = today.reduce(0) { $0 + $1.wordCount }
        let speakingMinutes = today.reduce(0) { $0 + $1.audioSeconds } / 60
        stats.minutesSaved = max(0, Double(stats.words) / Self.typingWordsPerMinute - speakingMinutes)
        if !today.isEmpty {
            stats.averageLatency = today.reduce(0) { $0 + $1.latencySeconds } / Double(today.count)
        }

        // Newest first, so this can stop at the first gap.
        let sql = "SELECT DISTINCT date(createdAt, 'localtime') AS day FROM dictation ORDER BY day DESC"
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let days = (try? db.read { try String.fetchAll($0, sql: sql) }) ?? []
        var expected = day
        for (index, text) in days.enumerated() {
            guard let date = formatter.date(from: text) else { break }
            if index == 0, date != expected { expected = calendar.date(byAdding: .day, value: -1, to: expected)! }
            guard date == expected else { break }
            stats.streakDays += 1
            expected = calendar.date(byAdding: .day, value: -1, to: expected)!
        }
        return stats
    }
}
