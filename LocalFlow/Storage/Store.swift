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

    // Since v0.3.
    /// The latest fix the user made in History. The pasted text stays in `finalText`.
    var fixedText: String? = nil
    /// When the user marked the text as what they said. A marked dictation keeps its audio until it's unmarked or deleted.
    var confirmedAt: Date? = nil
    /// The text that was marked as what they said.
    var confirmedText: String? = nil

    static let databaseTableName = "dictation"

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    var wordCount: Int { finalText.split(whereSeparator: \.isWhitespace).count }

    /// What to show, copy and paste again: the fix if there is one.
    var displayText: String { fixedText ?? finalText }
    var isConfirmed: Bool { confirmedAt != nil }

    /// EN, the other language's code (e.g. KO), or MIXED when a dictation in a non-Latin-script
    /// language also has English words. Mixing can't be told apart for Latin-script languages.
    var languageLabel: String {
        guard language != "en" else { return "EN" }
        let hasScript = SpokenLanguage.find(language)?.script != nil
        if hasScript, displayText.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil { return "MIXED" }
        return language.uppercased()
    }
}

/// One fix to a dictation's text: what it was before, and what it became.
struct DictationEdit: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: Int64?
    var dictationId: Int64
    var createdAt: Date
    /// "history" for a fix typed in History, "auto" for one seen in the app it was pasted into.
    var source: String
    var beforeText: String
    var afterText: String

    static let databaseTableName = "edit"
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// A Replacement LocalFlow offered after a fix. Answered once: accepted becomes a Replacement, declined isn't offered again.
struct Suggestion: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Equatable {
    enum Status: String, Codable { case pending, accepted, declined }

    var id: Int64?
    var find: String
    var replace: String
    var status: Status
    /// "history" or "auto", like `DictationEdit.source`.
    var source: String
    var createdAt: Date
    /// The fix it came from. Cleared, not deleted, when that dictation goes.
    var dictationId: Int64?

    static let databaseTableName = "suggestion"
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
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
    @Published private(set) var suggestions: [Suggestion] = []

    /// Dictations kept in memory, newest first, for the Home screen and the menu. History queries the database.
    static let recentLimit = 50

    private let db: DatabaseQueue
    private let directory: URL
    /// The database couldn't open. Everything on disk looks orphaned then, so nothing there gets deleted.
    private let isInMemoryFallback: Bool
    /// Why history isn't being saved this session, for the menu. Nil when the database is fine.
    let unavailableReason: String?
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
        let opened = Self.openDatabase(in: directory)
        db = opened.queue
        isInMemoryFallback = opened.failure != nil
        unavailableReason = opened.failure
        reloadDictionary()
        reloadRecent()
    }

    static let databaseName = "LocalFlow.sqlite"
    /// A copy taken just before a migration changes the file. Replaced by the next migration's copy, deleted after
    /// `backupKeepDays`, and with Delete all history.
    static let backupName = "LocalFlow.backup.sqlite"
    /// Days to keep the copy after a migration that went fine (owner, 2026-11-06). Longer, and dictations deleted one by one
    /// would live on in it.
    static let backupKeepDays = 7

    /// Deleted rows are overwritten with zeros instead of staying in the file's free pages.
    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA secure_delete = ON") }
        return configuration
    }

    private static func openDatabase(in directory: URL) -> (queue: DatabaseQueue, failure: String?) {
        do {
            let queue = try DatabaseQueue(path: directory.appendingPathComponent(databaseName).path, configuration: configuration)
            try backUpBeforeMigrating(queue, in: directory)
            try migrator.migrate(queue)
            // Not worth losing history over: a failure here leaves the file as it was.
            try? cleanFreePagesOnce(queue)
            return (queue, nil)
        } catch {
            // A broken database must not stop dictation. Fall back to memory for this session, and say so in the menu.
            NSLog("LocalFlow: database unavailable, using in-memory store: \(error.localizedDescription)")
            HealthCounter.count(.databaseUnavailable)
            let queue = try! DatabaseQueue()
            try! migrator.migrate(queue)
            return (queue, error.localizedDescription)
        }
    }

    /// `secure_delete` only covers deletes from now on. Text deleted before it may still sit in free pages, so the file is
    /// rewritten once. `user_version` records that, per file: GRDB's migrations don't use it.
    private static func cleanFreePagesOnce(_ queue: DatabaseQueue) throws {
        try queue.writeWithoutTransaction { db in
            guard try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0 < 1 else { return }
            try db.execute(sql: "VACUUM")
            try db.execute(sql: "PRAGMA user_version = 1")
        }
    }

    /// Data from before a migration can't be collected again, so a migration only runs once there's a copy. A failed copy stops it.
    private static func backUpBeforeMigrating(_ queue: DatabaseQueue, in directory: URL) throws {
        let needsCopy = try queue.read { db in try db.tableExists("dictation") && !migrator.hasCompletedMigrations(db) }
        guard needsCopy else { return }
        let url = directory.appendingPathComponent(backupName)
        try? FileManager.default.removeItem(at: url)
        let copy = try DatabaseQueue(path: url.path)
        try queue.backup(to: copy)
        try copy.close()
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
        migrator.registerMigration("v3") { db in
            try db.alter(table: "dictation") { t in
                t.add(column: "fixedText", .text)
                t.add(column: "confirmedAt", .datetime)
                t.add(column: "confirmedText", .text)
            }
            try db.create(table: "edit") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("dictation", onDelete: .cascade).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("source", .text).notNull()
                t.column("beforeText", .text).notNull()
                t.column("afterText", .text).notNull()
            }
            // One row per paste for automatic capture (M2): how watching it ended. Numbers and categories only, no text.
            try db.create(table: "pasteWatch") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("dictation", onDelete: .cascade).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("outcome", .text).notNull()
                t.column("endedBy", .text)
                t.column("secondsToEdit", .double)
            }
        }
        migrator.registerMigration("v4") { db in
            try db.create(table: "suggestion") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("find", .text).notNull()
                t.column("replace", .text).notNull()
                t.column("status", .text).notNull()
                t.column("source", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.belongsTo("dictation", onDelete: .setNull)
                t.uniqueKey(["find", "replace"])
            }
        }
        return migrator
    }

    private func reloadDictionary() {
        do {
            try db.read { db in
                vocabulary = try VocabularyTerm.order(Column("createdAt")).fetchAll(db)
                replacements = try Replacement.order(Column("createdAt")).fetchAll(db)
                suggestions = try Suggestion.order(Column("createdAt").desc).fetchAll(db)
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
        do {
            try db.write { db in try row.insert(db) }
        } catch {
            HealthCounter.count(.historySaveFailed)
        }
        dictations = Array(([row] + dictations).prefix(Self.recentLimit))
        revision += 1
        return row
    }

    /// Saves a fix typed in History. Returns false if there was nothing to save or it couldn't be saved.
    @discardableResult
    func fix(_ dictation: Dictation, to text: String, source: String = "history") -> Bool {
        guard let id = dictation.id, let fixed = FixText.normalized(text, replacing: dictation.displayText) else { return false }
        do {
            try db.write { db in
                var edit = DictationEdit(
                    dictationId: id, createdAt: Date(), source: source, beforeText: dictation.displayText, afterText: fixed
                )
                try edit.insert(db)
                // The mark was for the old text.
                try db.execute(
                    sql: "UPDATE dictation SET fixedText = ?, confirmedAt = NULL, confirmedText = NULL WHERE id = ?",
                    arguments: [fixed, id]
                )
            }
        } catch {
            HealthCounter.count(.historySaveFailed)
            return false
        }
        reloadRecent()
        return true
    }

    /// "This is what I said": marks the text shown now as a correct transcript, which keeps the audio past retention.
    func setConfirmed(_ dictation: Dictation, _ confirmed: Bool) {
        guard let id = dictation.id else { return }
        do {
            try db.write { db in
                try db.execute(
                    sql: "UPDATE dictation SET confirmedAt = ?, confirmedText = ? WHERE id = ?",
                    arguments: [confirmed ? Date() : nil, confirmed ? dictation.displayText : nil, id]
                )
            }
        } catch {
            HealthCounter.count(.historySaveFailed)
        }
        reloadRecent()
    }

    // MARK: Automatic capture

    /// Numbers only: how watching one paste ended, so "not edited" and "couldn't see" can be told apart.
    func recordPasteWatch(dictationId: Int64, outcome: String, endedBy: String?, secondsToEdit: Double?) {
        do {
            try db.write { db in
                try db.execute(
                    sql: "INSERT INTO pasteWatch (dictationId, createdAt, outcome, endedBy, secondsToEdit) VALUES (?, ?, ?, ?, ?)",
                    arguments: [dictationId, Date(), outcome, endedBy, secondsToEdit]
                )
            }
        } catch {
            HealthCounter.count(.historySaveFailed)
        }
    }

    /// After a fix seen in another app: a suggestion once the same fix has been seen enough times, on a word Whisper was unsure
    /// of. It waits in Dictionary › Suggestions.
    func suggestFromAutoFix(before: String, after: String, dictation: Dictation) {
        guard let pair = FixSuggestion.from(before: before, after: after),
              AutoFix.signal(before: before, after: after) == .substitution else { return }
        if replacements.contains(where: { $0.find == pair.find && $0.replace == pair.replace }) { return }
        if suggestions.contains(where: { $0.find == pair.find && $0.replace == pair.replace }) { return }
        let words = dictation.wordsJSON
            .flatMap { try? JSONDecoder().decode([Transcriber.Word].self, from: Data($0.utf8)) }?
            .map { (word: $0.word, probability: $0.probability) } ?? []
        guard AutoFix.wasUnsure(of: pair.find, words: words) else { return }
        let seen = (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT beforeText, afterText FROM edit WHERE source = 'auto'")
        })?.filter { FixSuggestion.from(before: $0["beforeText"], after: $0["afterText"]) == pair }.count ?? 0
        guard seen >= AutoFix.repeatsToSuggest else { return }
        var row = Suggestion(
            find: pair.find, replace: pair.replace, status: .pending, source: "auto", createdAt: Date(), dictationId: dictation.id
        )
        do {
            try db.write { db in try row.insert(db) }
        } catch {
            HealthCounter.count(.historySaveFailed)
            return
        }
        reloadDictionary()
    }

    // MARK: Suggestions

    /// The suggestion a fix leads to, if it's new: a pair already answered, or already a Replacement, isn't offered again.
    func suggestion(fromFix before: String, to after: String, dictation: Dictation) -> Suggestion? {
        guard let pair = FixSuggestion.from(before: before, after: after) else { return nil }
        if replacements.contains(where: { $0.find == pair.find && $0.replace == pair.replace }) { return nil }
        if let existing = suggestions.first(where: { $0.find == pair.find && $0.replace == pair.replace }) {
            return existing.status == .pending ? existing : nil
        }
        var row = Suggestion(
            find: pair.find, replace: pair.replace, status: .pending, source: "history", createdAt: Date(), dictationId: dictation.id
        )
        do {
            try db.write { db in try row.insert(db) }
        } catch {
            HealthCounter.count(.historySaveFailed)
            return nil
        }
        reloadDictionary()
        return row
    }

    /// How many stored dictations a rule for `find` would have changed, with a few of the words it would touch.
    func preview(find: String) -> (dictations: Int, words: [String]) {
        let texts = (try? db.read { try String.fetchAll($0, sql: "SELECT coalesce(fixedText, finalText) FROM dictation") }) ?? []
        var count = 0
        var words: [String] = []
        for text in texts {
            let matched = ReplacementEngine.matchedWords(find, in: text)
            guard !matched.isEmpty else { continue }
            count += 1
            for word in matched where !words.contains(word) && words.count < 3 { words.append(word) }
        }
        return (count, words)
    }

    func answer(_ suggestion: Suggestion, accept: Bool) {
        guard let id = suggestion.id else { return }
        if accept { addReplacement(find: suggestion.find, replace: suggestion.replace) }
        let status: Suggestion.Status = accept ? .accepted : .declined
        _ = try? db.write { db in
            try db.execute(sql: "UPDATE suggestion SET status = ? WHERE id = ?", arguments: [status.rawValue, id])
        }
        reloadDictionary()
    }

    /// A declined suggestion goes back to waiting for an answer.
    func askAgain(_ suggestion: Suggestion) {
        guard let id = suggestion.id else { return }
        _ = try? db.write { db in
            try db.execute(sql: "UPDATE suggestion SET status = 'pending' WHERE id = ?", arguments: [id])
        }
        reloadDictionary()
    }

    func edits(for dictation: Dictation) -> [DictationEdit] {
        guard let id = dictation.id else { return [] }
        return (try? db.read { try DictationEdit.filter(Column("dictationId") == id).order(Column("createdAt")).fetchAll($0) }) ?? []
    }

    func delete(_ dictation: Dictation) {
        guard let id = dictation.id else { return }
        _ = try? db.write { db in try Dictation.deleteOne(db, id: id) }
        try? FileManager.default.removeItem(at: audioURL(for: id))
        // The window may have to reach further back now. Suggestions from it lose their link.
        reloadRecent()
        reloadDictionary()
    }

    /// Deletes every dictation with its audio, fixes and paste rows, and the pre-migration copy. The Dictionary stays.
    func deleteAllHistory() {
        _ = try? db.write { db in try Dictation.deleteAll(db) }
        // Rewrites the file, so nothing deleted is left in it. Can't run inside a transaction.
        _ = try? db.writeWithoutTransaction { db in try db.execute(sql: "VACUUM") }
        try? FileManager.default.removeItem(at: audioDirectory)
        // In the fallback the real file is untouched, and the copy may be all that's left of it.
        if !isInMemoryFallback { try? FileManager.default.removeItem(at: backupURL) }
        reloadRecent()
        reloadDictionary()
    }

    private var backupURL: URL { directory.appendingPathComponent(Self.backupName) }

    /// The copy from before a migration, once it's older than `backupKeepDays`. The migration went fine if the database opened.
    private func pruneBackup(now: Date) {
        guard !isInMemoryFallback,
              let values = try? backupURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
              let made = values.creationDate ?? values.contentModificationDate,
              now.timeIntervalSince(made) > Double(Self.backupKeepDays) * 86_400 else { return }
        try? FileManager.default.removeItem(at: backupURL)
    }

    /// Applies the retention settings. Text: 0 = keep forever, -1 = keep nothing, N = keep N days.
    /// Audio follows its own number of days and goes when its row goes. Files without a row are removed.
    /// A dictation marked "This is what I said" keeps its text and audio until it's unmarked or deleted.
    func prune(retentionDays: Int, audioRetentionDays: Int, now: Date = Date()) {
        let textCutoff: Date? = switch retentionDays {
        case 0: nil
        case let days where days < 0: .distantFuture
        default: now.addingTimeInterval(-Double(retentionDays) * 86_400)
        }
        if let textCutoff {
            _ = try? db.write { db in
                try Dictation.filter(Column("createdAt") < textCutoff && Column("confirmedAt") == nil).deleteAll(db)
            }
        }
        pruneAudio(audioCutoff: now.addingTimeInterval(-Double(audioRetentionDays) * 86_400))
        pruneBackup(now: now)
        reloadRecent()
    }

    private func pruneAudio(audioCutoff: Date) {
        guard !isInMemoryFallback else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)) ?? []
        let saved = files.filter { $0.pathExtension == "wav" }
        guard !saved.isEmpty else { return }
        // A failed read must not look like "no rows", which would delete every file.
        guard let rows = try? db.read({ db in
            try Row.fetchAll(db, sql: "SELECT id, createdAt, confirmedAt FROM dictation").reduce(into: [Int64: (Date, Bool)]()) { result, row in
                result[row["id"]] = (row["createdAt"], (row["confirmedAt"] as Date?) != nil)
            }
        }) else { return }
        for file in saved {
            guard let id = Int64(file.deletingPathExtension().lastPathComponent) else { continue }
            if let (createdAt, confirmed) = rows[id], confirmed || createdAt >= audioCutoff { continue }
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
        let hasEnglish = "coalesce(fixedText, finalText) GLOB '*[A-Za-z][A-Za-z]*'"
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
            clauses.append(#"(finalText LIKE ? ESCAPE '\' OR rawText LIKE ? ESCAPE '\' OR fixedText LIKE ? ESCAPE '\')"#)
            arguments += [pattern, pattern, pattern]
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
