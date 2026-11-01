import AppKit

/// Presentation budget only: never changes the event's dates or timeline geometry.
struct CalendarCardLayout {
    let padding: CGFloat
    let titleLineHeight: CGFloat
    let metadataLineHeight: CGFloat
    let titleLines: Int
    let showsTime: Bool
    let completionSize: CGFloat
    let contentHeight: CGFloat
    let titleFontSize: CGFloat
    let metadataFontSize: CGFloat
    let gap: CGFloat = 2

    init(height: CGFloat, width: CGFloat, scale: CGFloat, font: HidigFontPreference, hasPriority: Bool = false) {
        padding = height < 28 ? 1 : (height < 54 ? 3 : 5)
        contentHeight = max(0, height - padding * 2 - (height >= 28 ? 4 : 0))
        var fittedTitleSize: CGFloat = 12
        while fittedTitleSize > 8 {
            if Self.metrics(font, size: fittedTitleSize * scale).lineHeight <= contentHeight { break }
            fittedTitleSize -= 0.5
        }
        titleFontSize = fittedTitleSize
        metadataFontSize = 10
        titleLineHeight = Self.metrics(font, size: fittedTitleSize * scale).lineHeight
        let metadata = Self.metrics(font, size: metadataFontSize * scale)
        metadataLineHeight = metadata.lineHeight
        completionSize = min(16, max(10, contentHeight - 4))
        let availableWidth = width - padding * 2 - completionSize - 7 - (hasPriority ? 14 : 0)
        showsTime = availableWidth >= metadata.timeWidth && contentHeight >= titleLineHeight + metadataLineHeight + gap
        let titleBudget = contentHeight - (showsTime ? metadataLineHeight + gap : 0)
        titleLines = max(1, min(3, Int(titleBudget / titleLineHeight)))
    }

    var requiredHeight: CGFloat {
        CGFloat(titleLines) * titleLineHeight + (showsTime ? metadataLineHeight + gap : 0)
    }

    private final class FontMetrics {
        let lineHeight: CGFloat
        let timeWidth: CGFloat
        init(_ font: NSFont) {
            lineHeight = ceil(font.ascender - font.descender + font.leading)
            timeWidth = ceil(("23:59–23:59" as NSString).size(withAttributes: [.font: font]).width)
        }
    }

    private static let metricsCache: NSCache<NSString, FontMetrics> = {
        let cache = NSCache<NSString, FontMetrics>()
        cache.countLimit = 256
        return cache
    }()

    private static func metrics(_ preference: HidigFontPreference, size: CGFloat) -> FontMetrics {
        let key = "\(preference.rawValue):\(Double(size).bitPattern)" as NSString
        if let cached = metricsCache.object(forKey: key) { return cached }
        let value = FontMetrics(nativeFont(preference, size: size))
        metricsCache.setObject(value, forKey: key)
        return value
    }

    static func nativeFont(_ preference: HidigFontPreference, size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        switch preference {
        case .system: return system
        case .rounded: return system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        case .serif: return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        case .monospaced: return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .avenir: return NSFont(name: "Avenir Next", size: size) ?? system
        case .golos, .onest, .manrope, .inter:
            return HidigFontRegistry.name(for: preference).flatMap { NSFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
        case .georgia: return NSFont(name: "Georgia", size: size) ?? system
        }
    }
}
