import AppKit

/// Only exposed by isolated QA builds, invoked through the app's own menu.
@MainActor enum HidigQAEvidence {
    static var lastCalendarGesture: [String: Any] = [:]
    static func captureWindow() {
        guard HidigRuntime.isIsolated, let path = HidigRuntime.environment["HIDIGFOCUS_EVIDENCE_DIR"],
              let window = NSApplication.shared.keyWindow, let content = window.contentView?.superview,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let stamp = "native-" + formatter.string(from: Date())
        try? data.write(to: directory.appendingPathComponent(stamp + ".png"))
        var dense: [[String: Any]] = []
        func visit(_ view: NSView) {
            if let view = view as? CalendarDenseAccessibilityView {
                dense.append(["frame": NSStringFromRect(view.frame), "bounds": NSStringFromRect(view.bounds),
                    "visibleRect": NSStringFromRect(view.visibleRect), "screenFrame": NSStringFromRect(view.accessibilityFrame()),
                    "items": view.elements.count, "firstFrame": view.elements.first.map { NSStringFromRect($0.accessibilityFrame()) } ?? "none"])
            }
            for child in view.subviews { visit(child) }
        }
        visit(content)
        let windowButtons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { type -> [String: Any]? in
            guard let button = window.standardWindowButton(type) else { return nil }
            return ["type": type.rawValue, "frameInWindow": NSStringFromRect(button.convert(button.bounds, to: nil)), "hidden": button.isHidden]
        }
        let metadata: [String: Any] = ["contentWidth": content.bounds.width, "contentHeight": content.bounds.height,
                                       "nativeWindowButtons": windowButtons, "contentLayoutRect": NSStringFromRect(window.contentLayoutRect),
                                       "windowIdentifier": window.identifier?.rawValue ?? "", "isolated": true,
                                       "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                       "qaReduceMotion": HidigRuntime.defaults.bool(forKey: "qa.reduceMotion"), "denseAccessibility": dense, "lastCalendarGesture": lastCalendarGesture]
        if let json = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: directory.appendingPathComponent(stamp + ".json"))
        }
    }
    static func resizeWindow(width: CGFloat, height: CGFloat) {
        guard HidigRuntime.isIsolated, let window = NSApplication.shared.keyWindow else { return }
        window.setContentSize(NSSize(width: width, height: height))
    }
}
