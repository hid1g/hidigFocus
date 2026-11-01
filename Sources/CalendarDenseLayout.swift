import AppKit

/// Presentation only. The complete day still determines overlap lanes and dates.
struct CalendarDenseItem: Identifiable, Equatable {
    let task: ManagedTask
    let rect: CGRect
    var id: UUID { task.id }
    init(task: ManagedTask, rect: CGRect) { self.task = task; self.rect = rect }
    init(task: ManagedTask, interval: PlannerInterval, placement: PlannerPlacement, width: CGFloat, hourHeight: CGFloat) {
        self.task = task
        let laneWidth = max(0, width - 4) / CGFloat(max(1, placement.laneCount))
        rect = CGRect(x: 2 + CGFloat(placement.lane) * laneWidth,
                      y: CGFloat(interval.start) / 60 * hourHeight,
                      width: max(1, laneWidth * CGFloat(placement.span) - 3),
                      height: max(1, CGFloat(interval.end - interval.start) / 60 * hourHeight))
    }
}
enum CalendarDensePart: Equatable { case body, completion, start, end }
struct CalendarDenseHit: Equatable {
    let id: UUID
    let part: CalendarDensePart
}
enum CalendarDenseLayout {
    static func drawingSlice(visible: CalendarVisibleMinutes, hourHeight: CGFloat) -> CGRect {
        let top = max(0, min(1440, visible.lower)) / 60 * hourHeight
        let bottom = max(visible.lower, min(1440, visible.upper)) / 60 * hourHeight
        return CGRect(x: 0, y: top, width: 0, height: max(1, bottom - top))
    }
    static func usesCanvas(taskCount: Int, override: String? = nil) -> Bool {
        if override == "legacy" { return false }
        if override == "canvas" { return true }
        return taskCount > 160
    }
    static func hit(_ point: CGPoint, items: [CalendarDenseItem]) -> CalendarDenseHit? {
        guard let item = items.reversed().first(where: { $0.rect.contains(point) }) else { return nil }
        let local = CGPoint(x: point.x - item.rect.minX, y: point.y - item.rect.minY)
        // Thin overlaps open details instead of accidentally completing a task.
        guard item.rect.width >= 32 else { return CalendarDenseHit(id: item.id, part: .body) }
        if local.x < 28, local.y < min(26, item.rect.height) { return CalendarDenseHit(id: item.id, part: .completion) }
        let edge = min(6, item.rect.height / 4)
        if local.x >= 28, local.y <= edge { return CalendarDenseHit(id: item.id, part: .start) }
        if local.x >= 28, local.y >= item.rect.height - edge { return CalendarDenseHit(id: item.id, part: .end) }
        return CalendarDenseHit(id: item.id, part: .body)
    }
}

/// Bounded drawing cache. No task text or dates are changed by fitting a label.
enum CalendarCanvasText {
    private final class Lines: NSObject { let values: [String]; init(_ values: [String]) { self.values = values } }
    private static let cache: NSCache<NSString, Lines> = { let c = NSCache<NSString, Lines>(); c.countLimit = 2048; return c }()
    static func lines(_ text: String, width: CGFloat, font: NSFont, limit: Int) -> [String] {
        guard width > 4, limit > 0 else { return [] }
        let key = "\(font.fontName):\(font.pointSize):\(Int(width * 2)):\(limit):\(text)" as NSString
        if let result = cache.object(forKey: key) { return result.values }
        var remaining = Array(text.replacingOccurrences(of: "\n", with: " "))
        var result: [String] = []
        func fits(_ value: String) -> Bool { (value as NSString).size(withAttributes: [.font: font]).width <= width }
        while !remaining.isEmpty, result.count < limit {
            if fits(String(remaining)) { result.append(String(remaining)); break }
            let last = result.count == limit - 1
            var lower = 0, upper = remaining.count
            while lower < upper {
                let middle = (lower + upper + 1) / 2
                if fits(String(remaining.prefix(middle)) + (last ? "…" : "")) { lower = middle }
                else { upper = middle - 1 }
            }
            guard lower > 0 else { break }
            if !last, let boundary = remaining.prefix(lower).lastIndex(of: " "), boundary > lower / 2 { lower = boundary }
            result.append(String(remaining.prefix(lower)) + (last ? "…" : ""))
            remaining.removeFirst(lower)
            while remaining.first == " " { remaining.removeFirst() }
        }
        cache.setObject(Lines(result), forKey: key)
        return result
    }
}
