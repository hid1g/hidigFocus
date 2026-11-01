import AppKit

/// A phased device supplies its own end-of-input signal. Silence while a finger
/// is down or native momentum is running must never start a competing day snap.
struct CalendarScrollLifecycle {
    enum Stream { case idle, gesture, awaitingMomentum, momentum, unphased }
    struct Deadline: Equatable {
        let time: TimeInterval
        let generation: UInt64
    }
    private(set) var stream: Stream = .idle
    private(set) var deadline: Deadline?
    private var generation: UInt64 = 0
    var isOpen: Bool { stream != .idle }

    mutating func reset() {
        generation &+= 1
        stream = .idle
        deadline = nil
    }

    /// Returns true for an explicit cancellation; the caller owns visual cleanup.
    @discardableResult
    mutating func observe(phase: NSEvent.Phase, momentum: NSEvent.Phase, at time: TimeInterval) -> Bool {
        generation &+= 1
        deadline = nil
        if phase.contains(.cancelled) || momentum.contains(.cancelled) {
            stream = .idle
            return true
        }
        if momentum.contains(.ended) {
            stream = .momentum
            deadline = Deadline(time: time, generation: generation)
        } else if !momentum.isEmpty {
            stream = .momentum
        } else if phase.contains(.ended) {
            // AppKit reports touch release before it starts native inertia.
            stream = .awaitingMomentum
            deadline = Deadline(time: time + 0.35, generation: generation)
        } else if !phase.isEmpty {
            stream = .gesture
        } else {
            // Traditional wheels do not provide phase/end events.
            stream = .unphased
            deadline = Deadline(time: time + 0.18, generation: generation)
        }
        return false
    }

    /// A cancelled queued block may already be runnable. Its generation cannot
    /// finish a later gesture or native-inertia stream.
    mutating func finish(_ expected: Deadline, at time: TimeInterval) -> Bool {
        guard deadline == expected, time >= expected.time else { return false }
        reset()
        return true
    }
}
