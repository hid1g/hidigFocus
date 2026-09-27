import Foundation

/// A single serial writer owns disk operations. Revision checks also reject stale callers.
final class SaveCoordinator {
    private let queue = DispatchQueue(label: "hidigFocus.persistence", qos: .utility)
    private var lastRevision: UInt64 = 0
    private let write: (PersistedAppState) throws -> Void
    init(repository: AppStateRepository) { write = repository.save }
    init(write: @escaping (PersistedAppState) throws -> Void) { self.write = write }
    func enqueue(_ state: PersistedAppState, revision: UInt64, completion: @escaping (UInt64, Result<Void, Error>) -> Void) {
        queue.async { [self] in
            guard revision > lastRevision else { completion(revision, .success(())); return }
            do { try write(state); lastRevision = revision; completion(revision, .success(())) }
            catch { completion(revision, .failure(error)) }
        }
    }
    func flush() { queue.sync {} }
}
