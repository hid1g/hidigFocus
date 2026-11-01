import AppKit
import CoreText
import SwiftUI

/// A QA process never shares preferences, notifications or network services with the live app.
enum HidigRuntime {
    static func qaEnvironment(bundleID: String?, configuration: [String: String]?) -> [String: String] {
        guard let bundleID, bundleID.hasPrefix("com.hidig.focus."), bundleID.hasSuffix(".qa"),
              let configuration, configuration["HIDIGFOCUS_QA"] == "1" else { return [:] }
        let allowed: Set<String> = ["HIDIGFOCUS_QA", "HIDIGFOCUS_DATA_DIR", "HIDIGFOCUS_PREFS_SUITE",
            "HIDIGFOCUS_EVIDENCE_DIR", "HIDIGFOCUS_QA_TASKS", "HIDIGFOCUS_QA_SERIES", "HIDIGFOCUS_CALENDAR_RENDERER"]
        return configuration.filter { allowed.contains($0.key) }
    }
    static let environment = qaEnvironment(bundleID: Bundle.main.bundleIdentifier,
        configuration: Bundle.main.infoDictionary?["HidigQAEnvironment"] as? [String: String])
        .merging(ProcessInfo.processInfo.environment) { _, explicit in explicit }
    static let isIsolated = environment["HIDIGFOCUS_QA"] == "1" || environment["HIDIGFOCUS_DATA_DIR"] != nil
    static let defaults: UserDefaults = {
        if let suite = environment["HIDIGFOCUS_PREFS_SUITE"] {
            // Foundation rejects adding the app's own preference domain as a suite.
            if suite == Bundle.main.bundleIdentifier { return .standard }
            if let defaults = UserDefaults(suiteName: suite) { return defaults }
            preconditionFailure("Cannot create isolated preference domain")
        }
        if isIsolated { return UserDefaults(suiteName: "com.hidig.focus.print.qa.preferences")! }
        return .standard
    }()
    static var servicesAllowed: Bool { !isIsolated }
}

enum PrintDesign {
    static let version = 1
    static let migrationKey = "printDesign.version"
    static let previousKey = "printDesign.previousAppearance"
    static let iconPackKey = "printDesign.iconPack"
    static let hover = PrintTokens.hover
    static let state = PrintTokens.state
    static let panel = PrintTokens.panel
    static let exit = 0.16
    static let appearanceKeys = [HidigSettingsKeys.font, HidigSettingsKeys.sidebarColor, HidigSettingsKeys.appIcon, iconPackKey]

    /// Only appearance keys are changed. The backup is written before changing a preference,
    /// and never replaced after a partially completed first launch.
    static func applyFirstLaunch(defaults: UserDefaults) {
        guard defaults.integer(forKey: migrationKey) < version else { return }
        if defaults.dictionary(forKey: previousKey) == nil {
            var previous: [String: Any] = [:]
            for key in appearanceKeys { if let value = defaults.object(forKey: key) { previous[key] = value } }
            previous["absentKeys"] = appearanceKeys.filter { defaults.object(forKey: $0) == nil }
            defaults.set(previous, forKey: previousKey)
            defaults.synchronize()
        }
        defaults.set("golos", forKey: HidigSettingsKeys.font)
        defaults.set("paper", forKey: HidigSettingsKeys.sidebarColor)
        defaults.set("doors", forKey: HidigSettingsKeys.appIcon)
        defaults.set("duotone", forKey: iconPackKey)
        defaults.set(version, forKey: migrationKey)
        defaults.synchronize()
    }
}

enum HidigFontRegistry {
    static let registration: Void = {
        for family in ["golostext", "onest", "manrope", "inter"] {
            guard let url = HidigResources.bundle.url(forResource: family, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    private static let names: [HidigFontPreference: String] = {
        _ = registration
        let candidates: [HidigFontPreference: String] = [.golos: "GolosText-Regular", .onest: "Onest-Regular", .manrope: "Manrope-Regular", .inter: "Inter-Regular"]
        return candidates.filter { NSFont(name: $0.value, size: 13) != nil }
    }()
    static func name(for preference: HidigFontPreference) -> String? { names[preference] }

}

enum HidigIconPack: String, CaseIterable, Identifiable {
    case outline, tiles, duotone
    var id: String { rawValue }
    var title: String { switch self { case .outline: return "Контур"; case .tiles: return "Плитки"; case .duotone: return "Двухтон" } }
}

/// Native symbol rendering, with one consistent scale and two tonal layers.
struct HidigNavigationIcon: View {
    let section: AppSection
    @AppStorage(PrintDesign.iconPackKey, store: HidigRuntime.defaults) private var packRaw = "duotone"
    var body: some View {
        let pack = HidigIconPack(rawValue: packRaw) ?? .duotone
        Image(systemName: section.systemImage)
            .symbolRenderingMode(pack == .duotone ? .hierarchical : .monochrome)
            .font(.system(size: 16, weight: pack == .outline ? .regular : .medium))
            .frame(width: 22, height: 24)
            .background(pack == .tiles ? Color.primary.opacity(0.09) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)
    }
}

@MainActor enum HidigTerminationGate { static var prepare: (() -> String?)? }

private struct HidigContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1100
}
private struct HidigReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}
extension EnvironmentValues {
    var hidigReduceMotion: Bool {
        get { self[HidigReduceMotionOverrideKey.self] ?? accessibilityReduceMotion }
        set { self[HidigReduceMotionOverrideKey.self] = newValue }
    }
    var hidigContentWidth: CGFloat {
        get { self[HidigContentWidthKey.self] }
        set { self[HidigContentWidthKey.self] = newValue }
    }
}

/// Exercise the real Reduce Motion branches without changing global macOS preferences.
struct HidigQAMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("qa.reduceMotion", store: HidigRuntime.defaults) private var forceReduceMotion = false
    func body(content: Content) -> some View {
        content.environment(\.hidigReduceMotion, systemReduceMotion || (HidigRuntime.isIsolated && forceReduceMotion))
    }
}

/// Writer-thread result used while the main actor is waiting for termination/selection.
final class HidigWriteReceipt: @unchecked Sendable {
    private let lock = NSLock()
    private var message: String?
    func record(_ result: Result<Void, Error>) {
        lock.lock(); defer { lock.unlock() }
        switch result { case .success: message = nil; case .failure(let error): message = error.localizedDescription }
    }
    var failure: String? { lock.lock(); defer { lock.unlock() }; return message }
}

struct HidigEmptyState: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).hidigFont(size: 18, weight: .medium)
            Text(detail).hidigFont(size: 13).foregroundStyle(HidigPalette.secondary)
            Button(actionTitle, action: action).buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
