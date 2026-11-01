import Foundation

/// The parent card includes completed and abandoned children regardless of planner filters.
enum TaskHierarchy {
    static func children(of parentID: UUID, in tasks: [ManagedTask]) -> [ManagedTask] {
        let parent = tasks.first { $0.id == parentID }
        let sourceOrder = Dictionary((parent?.tickTickBaseline?.childSourceIDs ?? []).enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return tasks.filter { $0.parentTaskID == parentID && $0.id != parentID && $0.status != .trashed }.sorted {
            let left = $0.sourceID.flatMap { sourceOrder[$0] } ?? Int.max
            let right = $1.sourceID.flatMap { sourceOrder[$0] } ?? Int.max
            if left != right { return left < right }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
