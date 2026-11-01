import Foundation

/// Serial disk writer for complete replacement snapshots. Only snapshots still waiting for
/// the writer may be superseded; every completion follows a committed write or its error.
final class SaveCoordinator {
    private typealias Completion = (UInt64, Result<Void, Error>) -> Void
    private struct Snapshot { let state: PersistedAppState; let revision: UInt64 }
    private let queue = DispatchQueue(label: "hidigFocus.persistence", qos: .utility)
    private let condition = NSCondition()
    private let queueKey = DispatchSpecificKey<Bool>()
    private var committedRevision: UInt64?
    private var highestRevision: UInt64 = 0
    private var pending: Snapshot?
    private var inFlightRevision: UInt64?
    private var lastFailure: Error?
    private var completions: [(UInt64, Completion)] = []
    private var isDraining = false
    private let write: (PersistedAppState) throws -> Void

    convenience init(repository: AppStateRepository) { self.init(write: repository.makeSaveOperation()) }
    init(write: @escaping (PersistedAppState) throws -> Void) {
        self.write = write
        queue.setSpecific(key: queueKey, value: true)
    }

    func enqueue(_ state: PersistedAppState, revision: UInt64, completion: @escaping (UInt64, Result<Void, Error>) -> Void) {
        condition.lock()
        if let committedRevision, revision <= committedRevision {
            // Keep callbacks on the writer, including already committed/stale requests.
            queue.async { completion(revision, .success(())) }
        } else if revision < highestRevision && pending == nil && inFlightRevision == nil, let error = lastFailure {
            // A failed newer snapshot must never be overwritten by a stale caller.
            queue.async { completion(revision, .failure(error)) }
        } else {
            completions.append((revision, completion))
            if revision > highestRevision || (pending == nil && inFlightRevision == nil && revision == highestRevision) {
                highestRevision = revision
                pending = Snapshot(state: state, revision: revision)
            }
            if !isDraining {
                isDraining = true
                queue.async { [self] in drain() }
            }
        }
        condition.unlock()
    }

    private func drain() {
        while true {
            condition.lock()
            guard let snapshot = pending else {
                isDraining = false
                condition.broadcast()
                condition.unlock()
                return
            }
            pending = nil
            inFlightRevision = snapshot.revision
            condition.unlock()

            let result: Result<Void, Error>
            do { try write(snapshot.state); result = .success(()) }
            catch { result = .failure(error) }

            condition.lock()
            if case .success = result {
                committedRevision = snapshot.revision
                lastFailure = nil
            } else if case .failure(let error) = result { lastFailure = error }
            inFlightRevision = nil
            let ready = completions.filter { $0.0 <= snapshot.revision }
            completions.removeAll { $0.0 <= snapshot.revision }
            condition.unlock()
            for (revision, completion) in ready { completion(revision, result) }
        }
    }

    /// Wait for the complete drain, including work enqueued by write completions.
    /// A callback is already on the serial writer and cannot synchronously wait for itself.
    func flush() {
        guard DispatchQueue.getSpecific(key: queueKey) != true else { return }
        while true {
            condition.lock()
            while isDraining { condition.wait() }
            condition.unlock()
            // Also finish callbacks for requests already committed when enqueued.
            queue.sync {}
            condition.lock()
            let finished = !isDraining
            condition.unlock()
            if finished { return }
        }
    }
    /// An empty queue is not proof that its last transaction succeeded.
    func flushFailure() -> Error? {
        flush()
        condition.lock(); defer { condition.unlock() }
        return lastFailure
    }

}
