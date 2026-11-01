import AppKit
import SwiftUI
import CoreVideo
import QuartzCore

/// CVDisplayLink supports macOS 13. Coalesce callbacks when the main thread is
/// busy instead of queuing one invalidation for every missed display refresh.
final class CalendarFrameClock {
    /// This box never retains or releases its owner on the display callback
    /// thread. The only weak-owner lookup happens inside the main-queue block.
    private final class Context {
        weak var clock: CalendarFrameClock?
        private let lock = NSLock()
        private var pending = false
        private var active = true
        init(_ clock: CalendarFrameClock) { self.clock = clock }
        func requestFrame() {
            lock.lock()
            guard active, !pending else { lock.unlock(); return }
            pending = true
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let active = self.active
                self.pending = false
                self.lock.unlock()
                guard active else { return }
                self.clock?.callback?(CACurrentMediaTime())
            }
        }
        func invalidate() {
            lock.lock(); active = false; pending = false; lock.unlock()
        }
    }
    private var link: CVDisplayLink?
    private var context: Context?
    private var fallback: Timer?
    private var callback: ((TimeInterval) -> Void)?

    func start(_ callback: @escaping (TimeInterval) -> Void) {
        stop()
        self.callback = callback
        let context = Context(self)
        self.context = context
        var displayLink: CVDisplayLink?
        if CVDisplayLinkCreateWithActiveCGDisplays(&displayLink) == kCVReturnSuccess, let displayLink {
            link = displayLink
            let registered = CVDisplayLinkSetOutputCallback(displayLink, { _, _, _, _, _, context in
                guard let context else { return kCVReturnSuccess }
                Unmanaged<Context>.fromOpaque(context).takeUnretainedValue().requestFrame()
                return kCVReturnSuccess
            }, Unmanaged.passUnretained(context).toOpaque())
            if registered == kCVReturnSuccess, CVDisplayLinkStart(displayLink) == kCVReturnSuccess { return }
            link = nil
        }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak context] _ in context?.requestFrame() }
        fallback = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stop() {
        context?.invalidate()
        // Keep the callback box alive until CVDisplayLinkStop has returned.
        if let link { CVDisplayLinkStop(link) }
        link = nil
        context = nil
        fallback?.invalidate(); fallback = nil
        callback = nil
    }
    deinit { stop() }
}

/// A non-observed sample channel. SwiftUI interpolation may report samples off
/// main; only the completion request crosses back to the main queue.
final class CalendarPresentationTracker {
    private let lock = NSLock()
    private var value: CGFloat = 0
    private var generation: UInt64 = 0
    private var target: CGFloat?
    private var reached = false
    var current: CGFloat { lock.lock(); defer { lock.unlock() }; return value }
    var token: UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
    func set(_ value: CGFloat) { lock.lock(); self.value = value; lock.unlock() }
    @discardableResult func begin(target: CGFloat) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; self.target = target; reached = false
        return generation
    }
    func cancel() {
        lock.lock(); generation &+= 1; target = nil; reached = false; lock.unlock()
    }
    func record(_ value: CGFloat, token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == token, let target else { return false }
        self.value = value
        guard !reached, abs(value - target) < 0.0001 else { return false }
        reached = true
        return true
    }
    func consumeCompletion(token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == token, reached, target != nil else { return false }
        target = nil; reached = false
        return true
    }
}

/// Offset is an action-level animation target. Presentation samples never publish
/// ObservableObject changes, preserving SwiftUI's native interpolation path.
final class CalendarPanState: ObservableObject {
    enum Phase { case idle, dragging, decelerating, settling }
    @Published var offset: CGFloat = 0 {
        didSet { if phase != .settling { presentation.set(offset) } }
    }
    @Published private(set) var phase: Phase = .idle
    var isAnimating: Bool { phase == .settling }
    var dayWidth: CGFloat = 200
    var allDayHeight: CGFloat = 36
    let presentation = CalendarPresentationTracker()
    private var completion: (() -> Void)?
    private var deadline: TimeInterval = 0
    var presentationToken: UInt64 { presentation.token }
    var visibleOffset: CGFloat { isAnimating ? presentation.current : offset }

    func interrupt() {
        let sample = visibleOffset
        presentation.cancel(); completion = nil
        phase = .idle
        setOffset(sample)
    }
    func beginInput(momentum: Bool, newGesture: Bool = false) {
        // A new stream takes ownership even if the previous stream was active.
        // Ordinary deltas only move the offset: re-interrupting each one publishes
        // an idle phase and the same offset, flushing the SwiftUI graph needlessly.
        if newGesture || (phase != .dragging && phase != .decelerating) { interrupt() }
        let inputPhase: Phase = momentum ? .decelerating : .dragging
        if phase != inputPhase { phase = inputPhase }
    }
    func reset() { interrupt(); setOffset(0) }
    func resizeDayWidth(to width: CGFloat, at time: TimeInterval = CACurrentMediaTime()) {
        let ratio = width / max(1, dayWidth)
        let previousTarget = isAnimating ? offset : nil
        let previousCompletion = completion
        let remaining = max(0.001, deadline - time)
        interrupt()
        setOffset(offset * ratio)
        dayWidth = width
        if let previousTarget {
            animate(to: previousTarget * ratio, reduceMotion: false, duration: remaining, at: time,
                    completion: previousCompletion)
        }
    }
    private func setOffset(_ value: CGFloat) {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { offset = value }
    }
    func animate(to target: CGFloat, reduceMotion: Bool, duration: TimeInterval = PrintDesign.state, at time: TimeInterval = CACurrentMediaTime(),
                 completion: (() -> Void)? = nil) {
        interrupt()
        guard !reduceMotion, duration > 0, abs(offset - target) > 0.1 else {
            setOffset(target); completion?(); return
        }
        self.completion = completion
        deadline = time + duration
        presentation.begin(target: target)
        phase = .settling
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration)) { offset = target }
    }
    func recordPresentation(_ value: CGFloat, token: UInt64) {
        guard presentation.record(value, token: token) else { return }
        DispatchQueue.main.async { [weak self] in self?.finishPresentation(token: token) }
    }
    func finishPresentation(token: UInt64) {
        guard presentation.consumeCompletion(token: token) else { return }
        let completed = completion
        completion = nil; phase = .idle
        completed?()
    }
    func completeImmediately() {
        guard isAnimating else { return }
        let target = offset
        let completed = completion
        interrupt(); setOffset(target)
        completed?()
    }
    func settle(reduceMotion: Bool, completion: (() -> Void)? = nil) {
        animate(to: 0, reduceMotion: reduceMotion, duration: 0.28, completion: completion)
    }
}

/// Only interpolated assignments report samples; constructing a new target does
/// not call the observer and cannot complete an animation before it starts.
struct CalendarObservedOffset: GeometryEffect {
    var value: CGFloat
    let leading: CGFloat
    let pan: CalendarPanState
    let token: UInt64
    var animatableData: CGFloat {
        get { value }
        set { value = newValue; pan.recordPresentation(newValue, token: token) }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: value - leading, y: 0))
    }
}

/// The persistent preference is updated only by finish(), including cancellation.
/// Intermediate magnification is view-local and cannot publish UserDefaults events.
struct CalendarZoomSession {
    private(set) var preview: Double?
    private var initial: Double?
    mutating func update(magnification: Double, persisted: Double) {
        guard magnification.isFinite, magnification > 0 else { return }
        if initial == nil { initial = CalendarZoom.clamp(persisted) }
        preview = CalendarZoom.clamp((initial ?? persisted) * magnification)
    }
    mutating func finish() -> Double? {
        defer { preview = nil; initial = nil }
        return preview
    }
}

/// Speed is points/second and ramps with penetration into the edge region.
/// Clamp long stalls: resuming a paused run loop must not teleport a dragged card.
enum CalendarAutoscrollMotion {
    static func delta(pointer: CGFloat, extent: CGFloat, edge: CGFloat = 40, elapsed: TimeInterval) -> CGFloat {
        guard extent > 0, edge > 0 else { return 0 }
        let penetration: CGFloat
        if pointer < edge { penetration = -min(1, max(0, (edge - pointer) / edge)) }
        else if pointer > extent - edge { penetration = min(1, max(0, (pointer - extent + edge) / edge)) }
        else { return 0 }
        return penetration * 480 * CGFloat(min(0.05, max(0, elapsed)))
    }
}

/// Queue ownership ends when a gesture interrupts button navigation.
struct CalendarNavigationQueue {
    private(set) var inFlight = false
    private(set) var pending = 0
    private(set) var epoch: UInt64 = 0
    mutating func enqueueIfBusy(_ direction: Int) -> Bool {
        guard inFlight else { return false }
        pending += direction < 0 ? -1 : 1
        return true
    }
    mutating func start() { inFlight = true }
    mutating func finish() { inFlight = false }
    mutating func cancel() { inFlight = false; pending = 0; epoch &+= 1 }
    mutating func next() -> Int? {
        guard pending != 0 else { return nil }
        let direction = pending > 0 ? 1 : -1
        pending -= direction
        return direction
    }
}

struct CalendarZoomAnchor {
    let minute: Double
    let localY: CGFloat
    init(contentOffset: CGFloat, localY: CGFloat, hourHeight: Double) {
        self.localY = localY
        minute = Double(contentOffset + localY) / max(1, hourHeight) * 60
    }
    func contentOffset(hourHeight: Double, viewportHeight: CGFloat) -> CGFloat {
        let offset = CGFloat(minute / 60 * hourHeight) - localY
        return min(max(0, CGFloat(hourHeight) * 24 - viewportHeight), max(0, offset))
    }
}
