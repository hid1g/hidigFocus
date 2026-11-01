import AppKit

/// Markdown grammar is line-local. Edits invalidate complete affected lines; selection
/// changes invalidate only the lines whose markers become visible/hidden.
final class MarkdownHighlighter {
    private static let bold = #"(\*\*)([^\n]+?)(\*\*)"#
    private static let italic = #"(?<!\*)(\*)([^*\n]+?)(\*)(?!\*)"#
    private static let code = #"(`)([^`\n]+?)(`)"#
    private static let headingRegex = try? NSRegularExpression(pattern: #"(?m)^(#{1,6})([ \t]+)(.*)$"#)
    private static let checklistRegex = try? NSRegularExpression(pattern: #"(?m)^([ \t]*)([-*+][ \t]+)(\[([ xX])\][ \t]+)(.*)$"#)
    private static let bulletRegex = try? NSRegularExpression(pattern: #"(?m)^([ \t]*)([-*+][ \t]+)(.*)$"#)
    private static let inlineRegex = Dictionary(uniqueKeysWithValues: [bold, italic, code].compactMap { pattern in (try? NSRegularExpression(pattern: pattern)).map { (pattern, $0) } })
    private var activeLines: NSRange?
    private var dirtyRange: NSRange?
    private var needsFullHighlight = true
    private(set) var lastStyledRanges: [NSRange] = []
    private(set) var stylingPassCount = 0
    var hasPendingEdits: Bool { needsFullHighlight || dirtyRange != nil }

    func reset() { needsFullHighlight = true; dirtyRange = nil; activeLines = nil }

    func edited(range: NSRange, changeInLength delta: Int, in storage: NSTextStorage) {
        if let activeLines { self.activeLines = mapped(activeLines, through: range, delta: delta) }
        if let dirtyRange { self.dirtyRange = mapped(dirtyRange, through: range, delta: delta) }
        // Include the character after the edit: inserting a newline splits the old
        // styled line, and the new trailing line also needs its inherited attrs reset.
        let end = min(storage.length, NSMaxRange(range) + 1)
        let affected = Self.lines(containing: NSRange(location: range.location, length: max(0, end - range.location)), in: storage.string as NSString)
        dirtyRange = dirtyRange.map { NSUnionRange($0, affected) } ?? affected
    }

    private func mapped(_ value: NSRange, through edit: NSRange, delta: Int) -> NSRange {
        let oldEnd = NSMaxRange(edit) - delta
        func position(_ offset: Int, isEnd: Bool) -> Int {
            if offset <= edit.location { return offset }
            if offset >= oldEnd { return max(0, offset + delta) }
            return isEnd ? NSMaxRange(edit) : edit.location
        }
        let start = position(value.location, isEnd: false)
        return NSRange(location: start, length: max(0, position(NSMaxRange(value), isEnd: true) - start))
    }

    @discardableResult
    func highlight(_ textView: NSTextView) -> Bool {
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return false }
        let source = storage.string as NSString
        let active = Self.lines(containing: textView.selectedRange(), in: source)
        var ranges: [NSRange] = []
        if needsFullHighlight { ranges = [NSRange(location: 0, length: storage.length)] }
        else {
            if let dirtyRange { ranges.append(Self.lines(containing: dirtyRange, in: source)) }
            if activeLines != active {
                if let activeLines { ranges.append(Self.lines(containing: activeLines, in: source)) }
                ranges.append(active)
            }
        }
        self.activeLines = active
        dirtyRange = nil
        needsFullHighlight = false
        let full = NSRange(location: 0, length: storage.length)
        ranges = ranges.map { NSIntersectionRange($0, full) }.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, NSMaxRange(last) >= range.location {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else { merged.append(range) }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 4
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        guard !merged.isEmpty else { textView.typingAttributes = base; return false }
        storage.beginEditing()
        for range in merged {
            storage.setAttributes(base, range: range)
            styleHeadings(in: storage, range: range, activeLineRange: active)
            styleLists(in: storage, range: range, activeLineRange: active)
            styleDelimited(pattern: Self.bold, range: range, contentFont: .boldSystemFont(ofSize: 16), in: storage, activeLineRange: active)
            styleDelimited(pattern: Self.italic, range: range, contentFont: NSFontManager.shared.convert(.systemFont(ofSize: 16), toHaveTrait: .italicFontMask), in: storage, activeLineRange: active)
            styleDelimited(pattern: Self.code, range: range, contentFont: .monospacedSystemFont(ofSize: 15, weight: .regular), in: storage, activeLineRange: active, background: NSColor.quaternaryLabelColor)
        }
        storage.endEditing()
        textView.typingAttributes = base
        lastStyledRanges = merged
        stylingPassCount += 1
        return true
    }

    static func lines(containing selection: NSRange, in source: NSString) -> NSRange {
        guard source.length > 0 else { return NSRange(location: 0, length: 0) }
        let location = min(max(0, selection.location), source.length - 1)
        let length = min(selection.length, source.length - location)
        return source.lineRange(for: NSRange(location: location, length: length))
    }
        private func styleHeadings(in storage: NSTextStorage, range: NSRange, activeLineRange: NSRange) {
            let source = storage.string
            let regex = Self.headingRegex
            let matches = regex?.matches(in: source, range: range) ?? []
            let sizes: [CGFloat] = [30, 25, 21, 19, 17, 16]

            for match in matches {
                let markerRange = NSUnionRange(match.range(at: 1), match.range(at: 2))
                let level = min(match.range(at: 1).length, sizes.count)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: sizes[level - 1], weight: .bold), range: match.range)
                styleDelimiter(markerRange, in: storage, activeLineRange: activeLineRange)
            }
        }

        private func styleLists(in storage: NSTextStorage, range: NSRange, activeLineRange: NSRange) {
            let source = storage.string
            let checkListRegex = Self.checklistRegex
            let checkListMatches = checkListRegex?.matches(
                in: source,
                range: range
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

            let bulletRegex = Self.bulletRegex
            let bulletMatches = bulletRegex?.matches(
                in: source,
                range: range
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
            range: NSRange,
            contentFont: NSFont,
            in storage: NSTextStorage,
            activeLineRange: NSRange,
            background: NSColor? = nil
        ) {
            let regex = Self.inlineRegex[pattern]
            let matches = regex?.matches(in: storage.string, range: range) ?? []
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


}

/// IME composition keeps its own temporary attributes until the marked range commits.
final class MarkdownTextView: NSTextView {
    var didEndMarkedText: (() -> Void)?
    override func unmarkText() {
        super.unmarkText()
        didEndMarkedText?()
    }
}
