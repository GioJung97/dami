import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DamiCore
import os

/// Watches pasted text for a while and saves a fix the user makes to it in place (v0.3 M2). Only the pasted span is kept,
/// never the text around it. Every paste gets a numbers-only row saying how watching ended.
@MainActor
final class PasteWatcher {
    static let shared = PasteWatcher()

    /// Where a paste went, taken by `TextInserter` around ⌘V.
    struct Target {
        let element: AXUIElement
        let pid: pid_t
        /// The text as pasted, with any leading space.
        let pasted: String
    }

    static let pollInterval: Duration = .seconds(1)
    /// Watching stops after this, at the latest (v0.3 §2).
    static let timeLimit: TimeInterval = 120
    /// Reads that may pass before the pasted text shows up in the field. Slow apps take the paste late.
    private static let locateAttempts = 3

    private enum Outcome: String { case edited, unchanged, spanLost, unreadable, notWatched, discarded }
    enum EndedBy: String {
        case appChanged, fieldChanged, nextDictation, timeLimit, spanLost, secureInput, unreadable, off, notPasted
    }

    private struct Watch {
        let dictation: Dictation
        let dictationId: Int64
        let target: Target
        let started = Date()
        var span: PasteSpan?
        var lastValue = ""
        var sawText = false
        var reads = 0
        var firstEdit: Date?
    }

    private let log = Logger(subsystem: "io.github.giojung97.dami", category: "capture")
    private var current: Watch?
    private var task: Task<Void, Never>?

    /// Starts watching a dictation that was just pasted. Ends any earlier watch first.
    func watch(_ dictation: Dictation, target: Target?) {
        finish(.nextDictation)
        guard let id = dictation.id else { return }
        guard AppSettings.shared.learnFromFixes else {
            Store.shared.recordPasteWatch(dictationId: id, outcome: Outcome.notWatched.rawValue, endedBy: EndedBy.off.rawValue, secondsToEdit: nil)
            return
        }
        guard let target else {
            Store.shared.recordPasteWatch(dictationId: id, outcome: Outcome.notWatched.rawValue, endedBy: EndedBy.notPasted.rawValue, secondsToEdit: nil)
            return
        }
        current = Watch(dictation: dictation, dictationId: id, target: target)
        poll()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self, self.current != nil else { return }
                self.poll()
            }
        }
    }

    /// Ends the watch, saving a fix if there is one.
    func finish(_ reason: EndedBy) {
        task?.cancel()
        task = nil
        guard let watch = current else { return }
        current = nil

        let outcome: Outcome
        var fixed: String?
        if reason == .off {
            outcome = .notWatched
        } else if reason == .spanLost {
            outcome = .spanLost
        } else if let span = watch.span, let text = span.text(in: watch.lastValue) {
            let before = AutoFix.normalized(watch.dictation.displayText)
            let after = AutoFix.normalized(text)
            if after == before {
                outcome = .unchanged
            } else if !PasteSpan.isPlausibleEdit(of: before, to: after) {
                outcome = .discarded
            } else {
                outcome = .edited
                fixed = after
            }
        } else {
            outcome = watch.sawText ? .spanLost : .unreadable
        }

        let store = Store.shared
        var savedFix = false
        if let fixed {
            savedFix = store.fix(watch.dictation, to: fixed, source: "auto")
            if savedFix { store.suggestFromAutoFix(before: watch.dictation.displayText, after: fixed, dictation: watch.dictation) }
        }
        let secondsToEdit = watch.firstEdit.map { $0.timeIntervalSince(watch.started) }
        store.recordPasteWatch(
            dictationId: watch.dictationId,
            outcome: (outcome == .edited && !savedFix ? Outcome.unchanged : outcome).rawValue,
            endedBy: reason.rawValue,
            secondsToEdit: outcome == .edited ? secondsToEdit : nil
        )
        log.info("watch ended: \(outcome.rawValue, privacy: .public) by \(reason.rawValue, privacy: .public)")
    }

    private func poll() {
        guard var watch = current else { return }
        guard AppSettings.shared.learnFromFixes else { return finish(.off) }
        guard Date().timeIntervalSince(watch.started) < Self.timeLimit else { return finish(.timeLimit) }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == watch.target.pid else { return finish(.appChanged) }
        // A password being typed anywhere: stop reading at once.
        guard !IsSecureEventInputEnabled() else { return finish(.secureInput) }
        guard let focused = FocusedField.element(), CFEqual(focused, watch.target.element) else { return finish(.fieldChanged) }
        guard FocusedField.current() != .secure else { return finish(.secureInput) }
        guard let value = FocusedField.value(of: focused) else { return finish(.unreadable) }
        watch.reads += 1
        if !value.isEmpty { watch.sawText = true }

        if var span = watch.span {
            switch span.update(from: watch.lastValue, to: value) {
            case .outside: break
            case .inside: if watch.firstEdit == nil { watch.firstEdit = Date() }
            case .lost:
                current = watch
                return finish(.spanLost)
            }
            watch.span = span
        } else if let span = PasteSpan.locate(watch.target.pasted, in: value, caret: FocusedField.caret(of: focused)) {
            watch.span = span
        } else if watch.reads >= Self.locateAttempts {
            current = watch
            return finish(watch.sawText ? .spanLost : .unreadable)
        }
        watch.lastValue = value
        current = watch
    }
}
