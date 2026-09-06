import AppKit
import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var store: AppStore
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

            HStack(spacing: 0) {
                entriesList.frame(width: 230)
                Divider().overlay(HidigPalette.line)
                editor
            }
            .foregroundStyle(HidigPalette.forest)
            .background(HidigPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 36)
        .sheet(isPresented: $showsGuide) { ObsidianGuideSheet(isPresented: $showsGuide) }
    }

    private var entriesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow(text: "Записи").padding(.bottom, 8)
                ForEach(store.journalEntries) { entry in
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
                    .buttonStyle(SelectionRowButtonStyle(isSelected: store.selectedJournalEntry?.id == entry.id))
                }
            }
            .padding(16)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    TextField("Название файла", text: $store.journalTitleDraft)
                        .textFieldStyle(HidigTextFieldStyle())
                        .onSubmit { store.renameSelectedJournalEntry() }
                        .disabled(store.selectedJournalEntry == nil)
                    Button("Переименовать") { store.renameSelectedJournalEntry() }
                        .buttonStyle(SecondaryButtonStyle())
                        .fixedSize()
                        .disabled(store.selectedJournalEntry == nil)
                }
                Text(store.journalSaveState.title)
                    .hidigFont(size: 9, weight: .medium)
                    .foregroundStyle(store.journalSaveState.isError ? HidigPalette.warning : HidigPalette.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ZStack(alignment: .topLeading) {
                LiveMarkdownEditor(text: Binding(
                    get: { store.journalDraft },
                    set: { store.updateJournalDraft($0) }
                ))
                .disabled(store.selectedJournalEntry == nil)

                if store.selectedJournalEntry != nil && store.journalDraft.isEmpty {
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

private struct LiveMarkdownEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
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

        context.coordinator.textView = textView
        context.coordinator.applyMarkdownStyles()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.binding = $text
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
        }
        context.coordinator.applyMarkdownStyles()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var binding: Binding<String>
        weak var textView: NSTextView?
        private var isApplyingStyles = false

        init(text: Binding<String>) {
            binding = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingStyles, let textView else { return }
            binding.wrappedValue = textView.string
            applyMarkdownStyles()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingStyles else { return }
            applyMarkdownStyles()
        }

        func applyMarkdownStyles() {
            guard let textView, let storage = textView.textStorage else { return }
            isApplyingStyles = true
            defer { isApplyingStyles = false }

            let selection = textView.selectedRange()
            let activeLineRange = lineRange(containing: selection, in: storage.string)
            let fullRange = NSRange(location: 0, length: storage.length)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            paragraph.paragraphSpacing = 4

            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ], range: fullRange)

            styleHeadings(in: storage, activeLineRange: activeLineRange)
            styleLists(in: storage, activeLineRange: activeLineRange)
            styleDelimited(pattern: #"(\*\*)([^\n]+?)(\*\*)"#, contentFont: .boldSystemFont(ofSize: 16), in: storage, activeLineRange: activeLineRange)
            styleDelimited(pattern: #"(?<!\*)(\*)([^*\n]+?)(\*)(?!\*)"#, contentFont: NSFontManager.shared.convert(.systemFont(ofSize: 16), toHaveTrait: .italicFontMask), in: storage, activeLineRange: activeLineRange)
            styleDelimited(pattern: #"(`)([^`\n]+?)(`)"#, contentFont: .monospacedSystemFont(ofSize: 15, weight: .regular), in: storage, activeLineRange: activeLineRange, background: NSColor.quaternaryLabelColor)
            storage.endEditing()

            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            textView.setSelectedRange(selection)
        }

        private func styleHeadings(in storage: NSTextStorage, activeLineRange: NSRange) {
            let source = storage.string
            let regex = try? NSRegularExpression(pattern: #"(?m)^(#{1,6})([ \t]+)(.*)$"#)
            let matches = regex?.matches(in: source, range: NSRange(location: 0, length: storage.length)) ?? []
            let sizes: [CGFloat] = [30, 25, 21, 19, 17, 16]

            for match in matches {
                let markerRange = NSUnionRange(match.range(at: 1), match.range(at: 2))
                let level = min(match.range(at: 1).length, sizes.count)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: sizes[level - 1], weight: .bold), range: match.range)
                styleDelimiter(markerRange, in: storage, activeLineRange: activeLineRange)
            }
        }

        private func styleLists(in storage: NSTextStorage, activeLineRange: NSRange) {
            let source = storage.string
            let checkListRegex = try? NSRegularExpression(pattern: #"(?m)^(\s*)([-*+]\s+)(\[([ xX])\]\s+)(.*)$"#)
            let checkListMatches = checkListRegex?.matches(
                in: source,
                range: NSRange(location: 0, length: storage.length)
            ) ?? []
            var checklistLineRanges = Set<NSRange>()

            for match in checkListMatches {
                let lineRange = (source as NSString).lineRange(for: match.range)
                checklistLineRanges.insert(lineRange)
                guard NSIntersectionRange(lineRange, activeLineRange).length == 0 else { continue }

                let checkedMarker = (source as NSString).substring(with: match.range(at: 4))
                let symbolName = checkedMarker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "square"
                    : "checkmark.square.fill"
                applyListSymbol(
                    symbolName,
                    symbolRange: match.range(at: 2),
                    hiddenRange: match.range(at: 3),
                    in: storage
                )
                if symbolName == "checkmark.square.fill" {
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 5))
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 5))
                }
            }

            let bulletRegex = try? NSRegularExpression(pattern: #"(?m)^(\s*)([-*+]\s+)(.*)$"#)
            let bulletMatches = bulletRegex?.matches(
                in: source,
                range: NSRange(location: 0, length: storage.length)
            ) ?? []
            for match in bulletMatches {
                let lineRange = (source as NSString).lineRange(for: match.range)
                guard !checklistLineRanges.contains(lineRange),
                      NSIntersectionRange(lineRange, activeLineRange).length == 0 else { continue }
                applyListSymbol("circle.fill", symbolRange: match.range(at: 2), hiddenRange: nil, in: storage)
            }
        }

        private func applyListSymbol(
            _ symbolName: String,
            symbolRange: NSRange,
            hiddenRange: NSRange?,
            in storage: NSTextStorage
        ) {
            guard symbolRange.length > 0,
                  let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return }
            let attachment = NSTextAttachment()
            attachment.image = image
            let side: CGFloat = symbolName == "circle.fill" ? 7 : 15
            attachment.bounds = NSRect(x: 0, y: -2, width: side, height: side)
            storage.addAttribute(.attachment, value: attachment, range: NSRange(location: symbolRange.location, length: 1))
            if symbolRange.length > 1 {
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 1)
                ], range: NSRange(location: symbolRange.location + 1, length: symbolRange.length - 1))
            }
            if let hiddenRange {
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 1)
                ], range: hiddenRange)
            }
        }

        private func styleDelimited(
            pattern: String,
            contentFont: NSFont,
            in storage: NSTextStorage,
            activeLineRange: NSRange,
            background: NSColor? = nil
        ) {
            let regex = try? NSRegularExpression(pattern: pattern)
            let matches = regex?.matches(in: storage.string, range: NSRange(location: 0, length: storage.length)) ?? []
            for match in matches {
                storage.addAttribute(.font, value: contentFont, range: match.range(at: 2))
                if let background {
                    storage.addAttribute(.backgroundColor, value: background, range: match.range(at: 2))
                }
                styleDelimiter(match.range(at: 1), in: storage, activeLineRange: activeLineRange)
                styleDelimiter(match.range(at: 3), in: storage, activeLineRange: activeLineRange)
            }
        }

        private func styleDelimiter(_ range: NSRange, in storage: NSTextStorage, activeLineRange: NSRange) {
            if NSIntersectionRange(range, activeLineRange).length > 0 {
                storage.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                ], range: range)
            } else {
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 1)
                ], range: range)
            }
        }

        private func lineRange(containing selection: NSRange, in source: String) -> NSRange {
            let string = source as NSString
            guard string.length > 0 else { return NSRange(location: 0, length: 0) }
            let location = min(selection.location, string.length - 1)
            let safeLength = min(selection.length, string.length - location)
            return string.lineRange(for: NSRange(location: location, length: safeLength))
        }
    }
}

private struct ObsidianGuideSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionEyebrow(text: "Интеграция без синхронизации")
            Text("Как подключить к Obsidian")
                .hidigFont(size: 26, weight: .bold, design: .rounded)
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
