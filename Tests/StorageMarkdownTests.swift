import AppKit
import SwiftUI
import XCTest
@testable import hidigFocus

final class StorageMarkdownTests: XCTestCase {
    private func state(_ title: String) -> PersistedAppState {
        var state = PersistedAppState(); state.managedTasks = [ManagedTask(title: title)]; return state
    }

    func testFirstRevisionZeroCompletesOnlyAfterItsWriteCommits() {
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let lock = NSLock(); var committed = false, completed = false
        let writer = SaveCoordinator { _ in
            started.signal(); release.wait()
            lock.lock(); committed = true; lock.unlock()
        }
        writer.enqueue(state("zero"), revision: 0) { revision, result in
            XCTAssertEqual(revision, 0)
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            lock.lock(); XCTAssertTrue(committed); completed = true; lock.unlock()
        }
        XCTAssertEqual(started.wait(timeout: .now() + 3), .success)
        lock.lock(); XCTAssertFalse(completed); lock.unlock()
        release.signal(); writer.flush()
        XCTAssertTrue(completed)
    }

    func testPendingSnapshotsCoalesceAndCompleteOnlyAfterCommit() {
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let lock = NSLock(); var writes: [String] = [], completed: [UInt64] = []
        let writer = SaveCoordinator { state in
            if state.managedTasks[0].title == "1" { started.signal(); release.wait() }
            lock.lock(); writes.append(state.managedTasks[0].title); lock.unlock()
        }
        writer.enqueue(state("1"), revision: 1) { rev, result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }; lock.lock(); completed.append(rev); lock.unlock()
        }
        XCTAssertEqual(started.wait(timeout: .now() + 3), .success)
        for revision in UInt64(2)...100 {
            writer.enqueue(state(String(revision)), revision: revision) { rev, result in
                if case .failure(let error) = result { XCTFail(error.localizedDescription) }
                lock.lock(); XCTAssertEqual(writes.last, "100"); completed.append(rev); lock.unlock()
            }
        }
        lock.lock(); XCTAssertTrue(completed.isEmpty); lock.unlock()
        release.signal(); writer.flush()
        XCTAssertEqual(writes, ["1", "100"])
        XCTAssertEqual(completed.sorted(), Array(UInt64(1)...100))
    }

    func testConcurrentBurstNeverOverwritesFreshState() {
        let lock = NSLock(); var writes: [UInt64] = []; var completions = 0
        let writer = SaveCoordinator { state in
            lock.lock(); writes.append(UInt64(state.managedTasks[0].title)!); lock.unlock()
        }
        DispatchQueue.concurrentPerform(iterations: 400) { value in
            let revision = UInt64(value + 1)
            writer.enqueue(state(String(revision)), revision: revision) { _, result in
                if case .failure(let error) = result { XCTFail(error.localizedDescription) }; lock.lock(); completions += 1; lock.unlock()
            }
        }
        writer.flush()
        XCTAssertEqual(completions, 400)
        XCTAssertEqual(writes.last, 400)
        XCTAssertEqual(writes, writes.sorted())
        XCTAssertEqual(Set(writes).count, writes.count)
    }

    func testFailedLatestCannotBeReplacedByStaleAndCanRetry() {
        enum Failure: Error { case disk }
        var shouldFail = true; var writes: [String] = [], failures = 0, successes = 0
        let writer = SaveCoordinator { state in
            if shouldFail { throw Failure.disk }
            writes.append(state.managedTasks[0].title)
        }
        let completion: (UInt64, Result<Void, Error>) -> Void = { _, result in
            switch result { case .success: successes += 1; case .failure: failures += 1 }
        }
        writer.enqueue(state("new"), revision: 3, completion: completion); writer.flush()
        writer.enqueue(state("old"), revision: 2, completion: completion); writer.flush()
        XCTAssertEqual(failures, 2); XCTAssertEqual(successes, 0)
        shouldFail = false
        writer.enqueue(state("new"), revision: 3, completion: completion); writer.flush()
        writer.enqueue(state("old"), revision: 1, completion: completion); writer.flush()
        XCTAssertEqual(writes, ["new"]); XCTAssertEqual(successes, 2)
    }

    func testFlushIncludesWritesEnqueuedByCompletionAndReentrantFlush() {
        var writes: [String] = []
        let writer = SaveCoordinator { writes.append($0.managedTasks[0].title) }
        writer.enqueue(state("first"), revision: 1) { _, _ in
            writer.flush()
            writer.enqueue(self.state("second"), revision: 2) { _, _ in }
        }
        writer.flush()
        XCTAssertEqual(writes, ["first", "second"])
        // This completion is queued separately because its revision is already committed.
        writer.enqueue(state("stale"), revision: 1) { _, _ in
            writer.enqueue(self.state("third"), revision: 3) { _, _ in }
        }
        writer.flush(); XCTAssertEqual(writes.last, "third")
    }

    func testRetryFromFailureCompletionIsNotLost() {
        enum Failure: Error { case disk }
        var attempts = 0, successes = 0
        let writer = SaveCoordinator { _ in attempts += 1; if attempts == 1 { throw Failure.disk } }
        writer.enqueue(state("latest"), revision: 2) { _, result in
            if case .failure = result {
                writer.enqueue(self.state("latest"), revision: 2) { _, result in
                    if case .failure(let error) = result { XCTFail(error.localizedDescription) }; successes += 1
                }
            }
        }
        writer.flush(); XCTAssertEqual(attempts, 2); XCTAssertEqual(successes, 1)
    }

    func testPersistentWriterRoundTripsSnapshotsAndBackups() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        let writer = SaveCoordinator(repository: repository)
        writer.enqueue(state("first"), revision: 1) { _, result in if case .failure(let error) = result { XCTFail(error.localizedDescription) } }
        writer.flush(); XCTAssertEqual(try repository.load().managedTasks[0].title, "first")
        let backup = try XCTUnwrap(repository.createBackup(label: "test"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        writer.enqueue(state("second"), revision: 2) { _, result in if case .failure(let error) = result { XCTFail(error.localizedDescription) } }
        writer.flush(); XCTAssertEqual(try repository.load().managedTasks[0].title, "second")
    }

    @MainActor private func editor(_ source: String) -> (MarkdownTextView, LiveMarkdownEditor.Coordinator) {
        _ = NSApplication.shared
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        view.isRichText = true; view.allowsUndo = true; view.string = source
        view.setSelectedRange(NSRange(location: 0, length: 0))
        var value = source
        let coordinator = LiveMarkdownEditor.Coordinator(text: Binding(get: { value }, set: { value = $0 }))
        coordinator.install(on: view)
        return (view, coordinator)
    }

    @MainActor func testNativeSelectionOnlyRestylesOldAndNewLines() {
        let source = "# First\nuntouched\n**Third**\n"
        let (view, coordinator) = editor(source)
        let pass = coordinator.highlighter.stylingPassCount
        view.setSelectedRange(NSRange(location: 2, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        XCTAssertEqual(coordinator.highlighter.stylingPassCount, pass)
        view.setSelectedRange(NSRange(location: 20, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        XCTAssertEqual(coordinator.highlighter.stylingPassCount, pass + 1)
        XCTAssertEqual(coordinator.highlighter.lastStyledRanges.reduce(0) { $0 + $1.length }, 18)
        XCTAssertEqual(view.string, source)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 20, length: 0))
        XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: 18, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
    }

    @MainActor func testNativeEditsClearStaleAttributesAndPreserveUndoSelection() {
        let source = "plain\n**bold** and `code`\n- [x] Done\n"
        let (view, coordinator) = editor(source)
        let storage = view.textStorage!
        XCTAssertNotNil(storage.attribute(.backgroundColor, at: 20, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.strikethroughStyle, at: 33, effectiveRange: nil))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        defer { window.orderOut(nil) }
        view.setSelectedRange(NSRange(location: 24, length: 1))
        view.insertText("", replacementRange: NSRange(location: 24, length: 1))
        XCTAssertNil(storage.attribute(.backgroundColor, at: 20, effectiveRange: nil))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 24, length: 0))
        XCTAssertLessThan(coordinator.highlighter.lastStyledRanges.reduce(0) { $0 + $1.length }, source.utf16.count)
        XCTAssertNotNil(view.undoManager)
        view.undoManager?.undo()
        XCTAssertEqual(view.string, source)
        XCTAssertNotNil(storage.attribute(.backgroundColor, at: 20, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.strikethroughStyle, at: 33, effectiveRange: nil))
        view.undoManager?.redo()
        XCTAssertEqual(view.string, (source as NSString).replacingCharacters(in: NSRange(location: 24, length: 1), with: ""))
    }

    @MainActor func testIMEPreservesMarkedTextThenHighlightsCommit() {
        let (view, coordinator) = editor("start\n")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let pass = coordinator.highlighter.stylingPassCount
        view.setMarkedText("**日本**", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        coordinator.applyMarkdownStyles()
        XCTAssertEqual(coordinator.highlighter.stylingPassCount, pass)
        view.unmarkText()
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.string, "**日本**start\n")
        XCTAssertGreaterThan(coordinator.highlighter.stylingPassCount, pass)
        XCTAssertEqual(view.selectedRange().length, 0)
    }

    @MainActor func testSwitchDuringIMEKeepsDocumentsAndUndoSeparate() {
        let (view, coordinator) = editor("Document A")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view; window.makeFirstResponder(view)
        defer { window.orderOut(nil) }
        view.insertText("old edit", replacementRange: NSRange(location: 0, length: 0))
        view.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0), replacementRange: view.selectedRange())
        XCTAssertTrue(view.hasMarkedText())
        var documentB = "Document B"
        coordinator.update(text: documentB, binding: Binding(get: { documentB }, set: { documentB = $0 }), documentID: "B")
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.string, "Document B")
        XCTAssertFalse(view.undoManager?.canUndo ?? true)
        view.unmarkText()
        view.insertText("!", replacementRange: NSRange(location: view.string.utf16.count, length: 0))
        XCTAssertEqual(documentB, "Document B!")
        view.undoManager?.undo()
        XCTAssertEqual(view.string, "Document B")
        XCTAssertEqual(documentB, "Document B")
        XCTAssertFalse(view.string.contains("Document A"))
    }

    @MainActor func testNewlinesUnicodeAndExternalReplacementMatchFullHighlight() {
        let (view, coordinator) = editor("# Заголовок\n- [x] Готово\n**жирный** и *курсив* `код`\nend")
        view.insertText("\n", replacementRange: NSRange(location: 15, length: 0))
        view.insertText("", replacementRange: NSRange(location: 10, length: 1))
        let selection = view.selectedRange()
        let full = NSTextView(); full.string = view.string; full.setSelectedRange(selection)
        let highlighter = MarkdownHighlighter(); highlighter.highlight(full)
        let actual = view.textStorage!, expected = full.textStorage!
        XCTAssertEqual(actual.string, expected.string)
        for offset in 0..<actual.length {
            let actualAttributes = actual.attributes(at: offset, effectiveRange: nil).filter { $0.key != .attachment }
            let expectedAttributes = expected.attributes(at: offset, effectiveRange: nil).filter { $0.key != .attachment }
            XCTAssertTrue(NSDictionary(dictionary: actualAttributes).isEqual(to: expectedAttributes), "offset \(offset)")
            XCTAssertEqual(actual.attribute(.attachment, at: offset, effectiveRange: nil) != nil, expected.attribute(.attachment, at: offset, effectiveRange: nil) != nil)
        }
        coordinator.replaceTextIfNeeded("# Новый\n*текст*")
        XCTAssertEqual(view.string, "# Новый\n*текст*")
    }

    @MainActor func testLongDocumentSelectionAndTypingWorkIsBounded() {
        let source = String(repeating: "**bold** and `code`\n", count: 10_000)
        let (view, coordinator) = editor(source)
        let start = CFAbsoluteTimeGetCurrent()
        for offset in 1...100 {
            view.setSelectedRange(NSRange(location: offset * 1000, length: 0))
            coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(coordinator.highlighter.lastStyledRanges.reduce(0) { $0 + $1.length }, 100)
        view.insertText("X", replacementRange: view.selectedRange())
        XCTAssertLessThan(coordinator.highlighter.lastStyledRanges.reduce(0) { $0 + $1.length }, 100)
        XCTAssertEqual(view.string.utf16.count, source.utf16.count + 1)
        print("Markdown 190k UTF16 / 100 native selection moves: \(elapsed * 1000) ms")
    }
}
