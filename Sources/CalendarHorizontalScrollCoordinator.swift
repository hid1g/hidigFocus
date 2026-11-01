import AppKit

final class CalendarHorizontalScrollCoordinator {
    weak var view: NSView?
    var isEnabled = false
    var onBegin: (() -> Bool)?
    var onScroll: ((CGFloat, Bool, Bool, Bool) -> Void)?
    var axis = CalendarAxisLock()
    var lifecycle = CalendarScrollLifecycle()
    var startedInside = false
    var needsHorizontalFinish = false
    var monitor: Any?
    var pendingFinish: DispatchWorkItem?
    func attach() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { cancelPending() }
    }
    private func cancelPending() {
        pendingFinish?.cancel(); pendingFinish = nil
        lifecycle.reset(); axis.reset(); startedInside = false
        needsHorizontalFinish = false
    }
    func detach() {
        cancelPending()
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
    }
    deinit { detach() }
    func handle(_ event: NSEvent) -> Bool {
        guard isEnabled, let view, event.window === view.window else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        return process(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                       phase: event.phase, momentum: event.momentumPhase,
                       inside: view.bounds.contains(point), at: ProcessInfo.processInfo.systemUptime)
    }
    /// The event adapter and regression tests share this routing path.
    @discardableResult
    func process(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase,
                 inside: Bool, at time: TimeInterval) -> Bool {
        guard isEnabled else { return false }
        let unphased = phase.isEmpty && momentum.isEmpty
        if phase.contains(.began) || (!lifecycle.isOpen && (unphased || phase.contains(.mayBegin))) {
            guard inside else { return false }
            // New input cancels the previous settle and takes its sampled
            // visible position. It must not first snap/commit the old stream.
            needsHorizontalFinish = (onBegin?() ?? false) || needsHorizontalFinish
            pendingFinish?.cancel(); pendingFinish = nil
            lifecycle.reset(); axis.reset()
            startedInside = true
        }
        // AppKit latches a phased stream to its starting view. The pointer can
        // leave it before a zero-delta terminal event, including a vertical turn.
        guard startedInside else { return false }
        pendingFinish?.cancel(); pendingFinish = nil
        let cancelled = lifecycle.observe(phase: phase, momentum: momentum,
                                          at: time)
        if cancelled {
            if needsHorizontalFinish { onScroll?(0, true, true, false) }
            axis.reset(); startedInside = false; needsHorizontalFinish = false
            return false
        }
        let accepted = axis.accept(dx: dx, dy: dy)
        if accepted { needsHorizontalFinish = true }
        if accepted, axis.horizontalDelta != 0 {
            onScroll?(axis.horizontalDelta, false, false, !momentum.isEmpty)
        }
        if let deadline = lifecycle.deadline {
            let work = DispatchWorkItem { [weak self] in
                self?.finish(deadline, at: ProcessInfo.processInfo.systemUptime)
            }
            pendingFinish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.time - time), execute: work)
        }
        return accepted
    }
    func finish(_ deadline: CalendarScrollLifecycle.Deadline, at time: TimeInterval) {
        guard lifecycle.finish(deadline, at: time) else { return }
        pendingFinish?.cancel(); pendingFinish = nil
        if needsHorizontalFinish { onScroll?(0, true, false, false) }
        axis.reset(); startedInside = false; needsHorizontalFinish = false
    }

}
