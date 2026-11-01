import SwiftUI

struct CalendarAllDayDropRegion {
    var bounds: CGRect = .zero
    func day(at point: CGPoint, anchor: Date, dayWidth: CGFloat, panOffset: CGFloat,
             calendar: Calendar = PlannerCalendar.current) -> Date? {
        guard dayWidth > 0, bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return nil }
        let shift = Int(floor((point.x - bounds.minX - panOffset) / dayWidth))
        return calendar.date(byAdding: .day, value: shift, to: calendar.startOfDay(for: anchor))
    }
}

struct CalendarAllDayDragActions {
    var update: (CGPoint?, ManagedTask?) -> Date? = { _, _ in nil }
}
private struct CalendarAllDayDragKey: EnvironmentKey {
    static let defaultValue = CalendarAllDayDragActions()
}
extension EnvironmentValues {
    var calendarAllDayDrag: CalendarAllDayDragActions {
        get { self[CalendarAllDayDragKey.self] }
        set { self[CalendarAllDayDragKey.self] = newValue }
    }
}
struct CalendarAllDayBounds: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}
final class CalendarAllDayPreview: ObservableObject {
    struct Item { let task: ManagedTask; let point: CGPoint }
    @Published var item: Item?
}
struct CalendarAllDayDragOverlay: View {
    @ObservedObject var preview: CalendarAllDayPreview
    @EnvironmentObject private var store: AppStore
    var body: some View {
        GeometryReader { geometry in
            if let item = preview.item {
                let bounds = geometry.frame(in: .global)
                let tint = Color(hex: store.taskList(id: item.task.listID)?.colorHex ?? "#6A9CC2")
                Text(item.task.title)
                    .hidigFont(size: 12, weight: .medium).lineLimit(1)
                    .padding(.horizontal, 8).frame(width: min(220, geometry.size.width), height: 25, alignment: .leading)
                    .background(HidigPalette.surfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.25)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .position(x: item.point.x - bounds.minX, y: item.point.y - bounds.minY)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
