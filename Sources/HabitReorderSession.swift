import SwiftUI

/// Preview never mutates persisted habits. Frozen row frames prevent target oscillation.
final class HabitReorderSession: ObservableObject {
    struct Drag {
        let source: UUID
        let order: [UUID]
        let frames: [UUID: CGRect]
        var target: UUID
        var translation: CGFloat
    }
    @Published private(set) var drag: Drag?

    func update(id: UUID, order: [UUID], frames: [UUID: CGRect], translation: CGFloat) {
        if drag == nil {
            guard frames[id] != nil, order.allSatisfy({ frames[$0] != nil }) else { return }
            drag = Drag(source: id, order: order, frames: frames, target: id, translation: 0)
        }
        guard var next = drag, next.source == id, let source = next.frames[id],
              let firstID = next.order.first, let lastID = next.order.last,
              let first = next.frames[firstID], let last = next.frames[lastID] else { return }
        next.translation = min(last.maxY - source.maxY, max(first.minY - source.minY, translation))
        let center = source.midY + next.translation
        next.target = next.order.min { abs(next.frames[$0]!.midY - center) < abs(next.frames[$1]!.midY - center) } ?? id
        drag = next
    }

    func offset(for id: UUID) -> CGFloat {
        guard let drag, let from = drag.order.firstIndex(of: drag.source),
              let to = drag.order.firstIndex(of: drag.target), let index = drag.order.firstIndex(of: id) else { return 0 }
        if id == drag.source { return drag.translation }
        let sourceFrame = drag.frames[drag.source]!
        let gap = drag.order.count > 1
            ? max(0, drag.frames[drag.order[1]]!.minY - drag.frames[drag.order[0]]!.maxY) : 0
        let stride = sourceFrame.height + gap
        if from < to, index > from && index <= to { return -stride }
        if to < from, index >= to && index < from { return stride }
        return 0
    }

    func finish() -> (source: UUID, target: UUID)? {
        defer { drag = nil }
        guard let drag, drag.source != drag.target else { return nil }
        return (drag.source, drag.target)
    }
    func cancel() { drag = nil }
}
