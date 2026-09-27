import Foundation

struct TaskHistoryEntry {
    let before: [ManagedTask]
    let after: [ManagedTask]
    func applying(to current: [ManagedTask], reverse: Bool) -> [ManagedTask] {
        let source = reverse ? after : before
        let target = reverse ? before : after
        let sourceByID = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
        let targetByID = Dictionary(uniqueKeysWithValues: target.map { ($0.id, $0) })
        var state = PersistedAppState(); state.managedTasks = current
        for id in Set(sourceByID.keys).union(targetByID.keys) where sourceByID[id] != targetByID[id] {
            switch (sourceByID[id], targetByID[id]) {
            case (nil, let value?): if !state.managedTasks.contains(where: { $0.id == id }) { state.managedTasks.append(value) }
            case (let value?, nil):
                // Never discard a task that changed independently after creation.
                if var current = state.managedTasks.first(where: { $0.id == id }) {
                    let expected = value
                    current.modifiedAt = expected.modifiedAt; current.changeHistory = expected.changeHistory
                    if current == expected { state.managedTasks.removeAll { $0.id == id } }
                }
            case (let original?, let draft?):
                guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { continue }
                TaskEngine.applyEdits(from: original, to: draft, in: &state)
                if original.status != draft.status { state.managedTasks[index].status = draft.status }
                if original.completedAt != draft.completedAt { state.managedTasks[index].completedAt = draft.completedAt }
                if original.deletedAt != draft.deletedAt { state.managedTasks[index].deletedAt = draft.deletedAt }
                if original.nextOccurrenceID != draft.nextOccurrenceID { state.managedTasks[index].nextOccurrenceID = draft.nextOccurrenceID }
                if original.sortOrder != draft.sortOrder { state.managedTasks[index].sortOrder = draft.sortOrder }
            default: break
            }
        }
        return state.managedTasks
    }
}
