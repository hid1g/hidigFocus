import AppKit
import SwiftUI

struct JournalView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var journal: JournalState
    @State private var showsGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                PageTitle(
                    eyebrow: "Локальные Markdown-файлы",
                    title: "Журнал",
                    subtitle: "Каждая запись — обычный .md файл. Его можно открыть и редактировать без hidigFocus."
                )
                Spacer()
                HStack(spacing: 8) {
                    Button { showsGuide = true } label: { Label("Obsidian", systemImage: "info.circle") }
                        .buttonStyle(SecondaryButtonStyle())
                        .fixedSize()
                    Button("Папка в Finder") { store.revealJournalFolder() }.buttonStyle(SecondaryButtonStyle())
                        .fixedSize()
                    Button("Новая запись") { store.createJournalEntry() }.buttonStyle(PrimaryButtonStyle())
                        .fixedSize()
                }
            }

            Group {
                if journal.journalEntries.isEmpty {
                    HidigEmptyState(title: "Записей пока нет", detail: "Создайте первую запись в журнале.", actionTitle: "Новая запись") { store.createJournalEntry() }
                } else {
                    HStack(spacing: 0) {
                        entriesList.frame(width: 190)
                        Divider().overlay(HidigPalette.line)
                        editor
                    }
                }
            }
            .foregroundStyle(HidigPalette.forest)
            .background(HidigPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 30)
        .sheet(isPresented: $showsGuide) { ObsidianGuideSheet(isPresented: $showsGuide) }
    }

    private var entriesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow(text: "Записи").padding(.bottom, 8)
                ForEach(journal.journalEntries) { entry in
                    Button { store.selectJournalEntry(entry) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).hidigFont(size: 12, weight: .semibold).lineLimit(2)
                            Text(entry.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                                .hidigFont(size: 9).foregroundStyle(HidigPalette.secondary)
                        }
                        .foregroundStyle(HidigPalette.forest)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SelectionRowButtonStyle(isSelected: journal.selectedJournalEntry?.id == entry.id))
                }
            }
            .padding(16)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    TextField("Название файла", text: $journal.journalTitleDraft)
                        .textFieldStyle(HidigTextFieldStyle())
                        .onSubmit { store.renameSelectedJournalEntry() }
                        .disabled(journal.selectedJournalEntry == nil)
                    Button("Переименовать") { store.renameSelectedJournalEntry() }
                        .buttonStyle(SecondaryButtonStyle())
                        .fixedSize()
                        .disabled(journal.selectedJournalEntry == nil)
                }
                if journal.journalSaveState.isError { Button("Повторить сохранение") { store.retryJournalSave() } }
                Text(journal.journalSaveState.title)
                    .hidigFont(size: 9, weight: .medium)
                    .foregroundStyle(journal.journalSaveState.isError ? HidigPalette.warning : HidigPalette.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ZStack(alignment: .topLeading) {
                LiveMarkdownEditor(text: Binding(
                    get: { journal.journalDraft },
                    set: { [entryID = journal.selectedJournalEntry?.id] value in
                        guard journal.selectedJournalEntry?.id == entryID else { return }
                        store.updateJournalDraft(value)
                    }
                ), documentID: journal.selectedJournalEntry?.id)
                .disabled(journal.selectedJournalEntry == nil)

                if journal.selectedJournalEntry != nil && journal.journalDraft.isEmpty {
                    Text("Начните писать…")
                        .hidigFont(size: 14, design: .monospaced)
                        .foregroundStyle(HidigPalette.secondary.opacity(0.72))
                        .padding(.leading, 17)
                        .padding(.top, 13)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

struct LiveMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var documentID: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, documentID: documentID)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.install(on: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(text: text, binding: $text, documentID: documentID)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var binding: Binding<String>
        weak var textView: NSTextView?
        let highlighter = MarkdownHighlighter()
        private var documentID: String?
        private var isApplyingStyles = false
        private var isReplacingText = false

        init(text: Binding<String>, documentID: String? = nil) {
            binding = text
            self.documentID = documentID
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(undoDidFinish(_:)), name: .NSUndoManagerDidUndoChange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(undoDidFinish(_:)), name: .NSUndoManagerDidRedoChange, object: nil)
        }
        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func undoDidFinish(_ notification: Notification) {
            guard let manager = notification.object as? UndoManager, manager === textView?.undoManager, let textView else { return }
            if binding.wrappedValue != textView.string { binding.wrappedValue = textView.string }
            applyMarkdownStyles(afterUndo: true)
        }

        func install(on textView: NSTextView) {
            self.textView = textView
            textView.delegate = self
            textView.textStorage?.delegate = self
            (textView as? MarkdownTextView)?.didEndMarkedText = { [weak self] in self?.applyMarkdownStyles() }
            applyMarkdownStyles()
        }

        func update(text: String, binding: Binding<String>, documentID: String?) {
            if self.documentID != documentID, let textView {
                // End the old composition while callbacks are suppressed, before
                // replacing its binding. Its marked contents cannot enter another file.
                isReplacingText = true
                textView.unmarkText()
                textView.undoManager?.removeAllActions()
                self.binding = binding
                self.documentID = documentID
                let selection = textView.selectedRange()
                textView.string = text
                highlighter.reset()
                let location = min(selection.location, text.utf16.count)
                textView.setSelectedRange(NSRange(location: location, length: min(selection.length, text.utf16.count - location)))
                isReplacingText = false
                applyMarkdownStyles()
            } else {
                self.binding = binding
                replaceTextIfNeeded(text)
            }
        }

        func detach() {
            textView?.delegate = nil
            textView?.textStorage?.delegate = nil
            (textView as? MarkdownTextView)?.didEndMarkedText = nil
            textView = nil
        }

        func replaceTextIfNeeded(_ text: String) {
            guard let textView, textView.string != text, !textView.hasMarkedText() else { return }
            let selection = textView.selectedRange()
            isReplacingText = true
            textView.string = text
            isReplacingText = false
            highlighter.reset()
            let location = min(selection.location, text.utf16.count)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, text.utf16.count - location)))
            applyMarkdownStyles()
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard !isApplyingStyles, !isReplacingText else { return }
            let undoing = textView?.undoManager.map { $0.isUndoing || $0.isRedoing } ?? false
            guard editedMask.contains(.editedCharacters) || undoing else { return }
            highlighter.edited(range: editedRange, changeInLength: delta, in: textStorage)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingStyles, !isReplacingText, let textView else { return }
            if binding.wrappedValue != textView.string { binding.wrappedValue = textView.string }
            applyMarkdownStyles()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // NSTextView adjusts selection while processing a character edit. Wait for
            // textDidChange so attributes never run inside that edit/IME transaction.
            guard !isApplyingStyles, !isReplacingText, !highlighter.hasPendingEdits else { return }
            applyMarkdownStyles()
        }

        func applyMarkdownStyles(afterUndo: Bool = false) {
            guard !isApplyingStyles, !isReplacingText, let textView else { return }
            if !afterUndo, let manager = textView.undoManager, manager.isUndoing || manager.isRedoing { return }
            isApplyingStyles = true
            defer { isApplyingStyles = false }
            highlighter.highlight(textView)
        }
    }

}

private struct ObsidianGuideSheet: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionEyebrow(text: "Интеграция без синхронизации")
            Text("Как подключить к Obsidian")
                .hidigFont(size: 26, weight: .bold)
            Text("Obsidian умеет открывать папки с Markdown-файлами. Вы можете добавить папку журнала hidigFocus в существующее хранилище или открыть её как отдельное хранилище.")
                .foregroundStyle(HidigPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                guideStep("1", "Нажмите «Открыть папку журнала».")
                guideStep("2", "В Obsidian выберите «Открыть папку как хранилище».")
                guideStep("3", "Укажите папку Journal. Новые записи hidigFocus будут появляться там автоматически.")
            }
            HStack {
                Button("Открыть папку журнала") { store.revealJournalFolder() }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Готово") { isPresented = false }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 520)
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.canvas)
    }

    private func guideStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).hidigFont(size: 11, weight: .bold).frame(width: 24, height: 24)
                .background(HidigPalette.lettuce).clipShape(Circle())
            Text(text).hidigFont(size: 13).padding(.top, 3)
        }
    }
}
