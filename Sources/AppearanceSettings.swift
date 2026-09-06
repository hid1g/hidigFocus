import AppKit
import ServiceManagement
import SwiftUI

enum HidigSettingsKeys {
    static let appearance = "appearancePreference"
    static let font = "fontPreference"
    static let textSize = "textSizePreference"
    static let sidebarColor = "sidebarColorPreference"
    static let customSidebarColor = "customSidebarColorHex"
    static let appIcon = "appIconPreference"
    static let showDockIcon = "showDockIcon"
    static let openWindowOnLaunch = "openWindowOnLaunch"
}

enum HidigFontPreference: String, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced
    case avenir
    case georgia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системный"
        case .rounded: return "Округлый"
        case .serif: return "Классический"
        case .monospaced: return "Моно"
        case .avenir: return "Avenir"
        case .georgia: return "Georgia"
        }
    }

    func font(size: CGFloat, weight: Font.Weight, design: Font.Design?) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight, design: design ?? .default)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .monospaced:
            return .system(size: size, weight: weight, design: .monospaced)
        case .avenir:
            return .custom("Avenir Next", fixedSize: size).weight(weight)
        case .georgia:
            return .custom("Georgia", fixedSize: size).weight(weight)
        }
    }
}

enum HidigTextSizePreference: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Компактный"
        case .standard: return "Обычный"
        case .large: return "Крупный"
        }
    }

    var scale: CGFloat {
        switch self {
        case .compact: return 0.94
        case .standard: return 1
        case .large: return 1.1
        }
    }
}

private struct HidigFontPreferenceKey: EnvironmentKey {
    static let defaultValue = HidigFontPreference.system
}

private struct HidigTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var hidigFontPreference: HidigFontPreference {
        get { self[HidigFontPreferenceKey.self] }
        set { self[HidigFontPreferenceKey.self] = newValue }
    }

    var hidigTextScale: CGFloat {
        get { self[HidigTextScaleKey.self] }
        set { self[HidigTextScaleKey.self] = newValue }
    }
}

private struct HidigFontModifier: ViewModifier {
    @Environment(\.hidigFontPreference) private var preference
    @Environment(\.hidigTextScale) private var scale

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design?

    func body(content: Content) -> some View {
        content.font(preference.font(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    func hidigFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design? = nil
    ) -> some View {
        modifier(HidigFontModifier(size: size, weight: weight, design: design))
    }
}

enum SidebarColorPreference: String, CaseIterable, Identifiable {
    case sage
    case cream
    case graphite
    case lavender
    case rose
    case ocean

    static let allCases: [SidebarColorPreference] = [.sage, .graphite, .ocean, .cream, .lavender, .rose]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sage: return "Стандартная"
        case .cream: return "Solarized"
        case .graphite: return "Графит"
        case .lavender: return "Сумерки"
        case .rose: return "Розовый кварц"
        case .ocean: return "Nord"
        }
    }

    var hex: String {
        theme(isDark: false).sidebar
    }

    var accentHex: String {
        theme(isDark: false).accent
    }

    func theme(isDark: Bool) -> HidigThemeColors {
        switch self {
        case .sage:
            return isDark
                ? HidigThemeColors(canvas: "#101611", sidebar: "#182019", surface: "#1C251E", surfaceRaised: "#222D25", line: "#34463A", accentSoft: "#36543A", accent: "#84B77D", text: "#EEF5EC", secondary: "#A9B8A8", hover: "#29382D", disabled: "#202A22")
                : HidigThemeColors(canvas: "#F6F8F2", sidebar: "#E5EFDA", surface: "#FBFCF8", surfaceRaised: "#FFFFFF", line: "#CBD9C3", accentSoft: "#D7E7D0", accent: "#507E4B", text: "#173B2A", secondary: "#657267", hover: "#D9E8CF", disabled: "#EEF3E9")
        case .graphite:
            return isDark
                ? HidigThemeColors(canvas: "#101112", sidebar: "#18191A", surface: "#1E2022", surfaceRaised: "#25272A", line: "#3A3D40", accentSoft: "#33373A", accent: "#A8ADB2", text: "#F1F2F2", secondary: "#A9ADB0", hover: "#292C2F", disabled: "#222426")
                : HidigThemeColors(canvas: "#F4F4F3", sidebar: "#E5E5E3", surface: "#FAFAF9", surfaceRaised: "#FFFFFF", line: "#CCCCCA", accentSoft: "#E0E2E3", accent: "#555B60", text: "#202326", secondary: "#6C7073", hover: "#DDDFE0", disabled: "#ECEDEC")
        case .ocean:
            return isDark
                ? HidigThemeColors(canvas: "#2E3440", sidebar: "#252B35", surface: "#343B49", surfaceRaised: "#3B4352", line: "#4C566A", accentSoft: "#3C5268", accent: "#88C0D0", text: "#ECEFF4", secondary: "#B5C0D0", hover: "#3B4351", disabled: "#343A46")
                : HidigThemeColors(canvas: "#ECEFF4", sidebar: "#E5E9F0", surface: "#F8F9FB", surfaceRaised: "#FFFFFF", line: "#C5CED9", accentSoft: "#D8E5ED", accent: "#5E81AC", text: "#2E3440", secondary: "#5A6575", hover: "#DCE5EE", disabled: "#E5E9EF")
        case .cream:
            return isDark
                ? HidigThemeColors(canvas: "#002B36", sidebar: "#073642", surface: "#0B3540", surfaceRaised: "#103F4B", line: "#33565E", accentSoft: "#154E52", accent: "#2AA198", text: "#EEE8D5", secondary: "#93A1A1", hover: "#12434D", disabled: "#0A3640")
                : HidigThemeColors(canvas: "#FDF6E3", sidebar: "#EEE8D5", surface: "#FFFBED", surfaceRaised: "#FFFFF7", line: "#D9CFB5", accentSoft: "#DCE7DC", accent: "#268BD2", text: "#073642", secondary: "#657B83", hover: "#EAE3CE", disabled: "#F3EBD7")
        case .lavender:
            return isDark
                ? HidigThemeColors(canvas: "#15111C", sidebar: "#1E1828", surface: "#251E30", surfaceRaised: "#2D2539", line: "#493C59", accentSoft: "#4A3A5F", accent: "#B497D6", text: "#F2ECF8", secondary: "#B7A9C5", hover: "#342A42", disabled: "#251E2F")
                : HidigThemeColors(canvas: "#F5F1FA", sidebar: "#E9E1F3", surface: "#FCFAFE", surfaceRaised: "#FFFFFF", line: "#D1C4DF", accentSoft: "#E5D9F1", accent: "#8064A2", text: "#30253F", secondary: "#756982", hover: "#E6DCF0", disabled: "#F0EAF5")
        case .rose:
            return isDark
                ? HidigThemeColors(canvas: "#1B1116", sidebar: "#271820", surface: "#301E27", surfaceRaised: "#39232E", line: "#5A3947", accentSoft: "#5C3545", accent: "#D889A4", text: "#FAEDF2", secondary: "#C2A4B0", hover: "#402833", disabled: "#2D1C24")
                : HidigThemeColors(canvas: "#FFF4F7", sidebar: "#F5E2E9", surface: "#FFFAFB", surfaceRaised: "#FFFFFF", line: "#E1C6D0", accentSoft: "#F1D9E2", accent: "#A95F79", text: "#442B34", secondary: "#806872", hover: "#F0DCE4", disabled: "#F8EAF0")
        }
    }
}

struct HidigThemeColors {
    let canvas: String
    let sidebar: String
    let surface: String
    let surfaceRaised: String
    let line: String
    let accentSoft: String
    let accent: String
    let text: String
    let secondary: String
    let hover: String
    let disabled: String
}

enum AppIconPreference: String, CaseIterable, Identifiable {
    case light
    case green
    case dark
    case purple
    case aurora
    case rose

    static let allCases: [AppIconPreference] = [.green, .light, .dark, .rose]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Светлая"
        case .green: return "Оригинал"
        case .dark: return "Графитовая"
        case .purple: return "Фиолетовая"
        case .aurora: return "Аврора"
        case .rose: return "Розовая"
        }
    }

    var hueRotation: Angle {
        switch self {
        case .light, .green, .dark: return .zero
        case .purple: return .degrees(78)
        case .aurora: return .degrees(318)
        case .rose: return .degrees(220)
        }
    }

    var saturation: Double {
        switch self {
        case .light: return 0.52
        case .green: return 1
        case .dark: return 0
        case .purple, .rose: return 0.9
        case .aurora: return 1.18
        }
    }

    var brightness: Double {
        switch self {
        case .light: return 0.12
        case .green, .purple, .aurora, .rose: return 0
        case .dark: return -0.12
        }
    }

    var normalized: AppIconPreference {
        switch self {
        case .purple, .aurora: return .rose
        default: return self
        }
    }
}

struct AppIconPreview: View {
    let style: AppIconPreference
    var size: CGFloat = 48

    var body: some View {
        let resolved = style.normalized
        ZStack {
            Image(nsImage: AppIconController.originalIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .hueRotation(resolved.hueRotation)
                .saturation(resolved.saturation)
                .brightness(resolved.brightness)
                .contrast(resolved == .dark ? 1.18 : 1)
        }
        .frame(width: size, height: size)
    }
}

enum AppAppearanceController {
    @MainActor
    static func apply(_ preference: AppearancePreference) {
        switch preference {
        case .system:
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum AppIconController {
    static let originalIcon: NSImage = {
        if let url = Bundle.module.url(forResource: "hidigFocus-icon-master", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return (NSApplication.shared.applicationIconImage.copy() as? NSImage)
            ?? NSImage(size: NSSize(width: 1024, height: 1024))
    }()

    @MainActor
    static func apply(_ style: AppIconPreference) {
        let renderer = ImageRenderer(content: AppIconPreview(style: style.normalized, size: 1024))
        renderer.scale = 1
        if let image = renderer.nsImage {
            NSApplication.shared.applicationIconImage = image
            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            NSApplication.shared.dockTile.contentView = imageView
            NSApplication.shared.dockTile.display()
        }
    }
}

enum ApplicationDockController {
    @MainActor
    static func apply(showDockIcon: Bool, icon: AppIconPreference) {
        let desiredPolicy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        if NSApplication.shared.activationPolicy() != desiredPolicy {
            NSApplication.shared.setActivationPolicy(desiredPolicy)
            DispatchQueue.main.async {
                AppIconController.apply(icon)
            }
        } else {
            AppIconController.apply(icon)
        }
    }
}

enum LaunchAtLoginController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(value, radix: 16) ?? 0
        let red = Double((number >> 16) & 0xff) / 255
        let green = Double((number >> 8) & 0xff) / 255
        let blue = Double(number & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}

enum SidebarColorResolver {
    static func color(preference: SidebarColorPreference?, customHex: String) -> Color {
        Color(hex: preference?.hex ?? customHex)
    }

    static func foreground(preference: SidebarColorPreference?, customHex: String) -> Color {
        let hex = (preference?.hex ?? customHex).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let number = UInt64(hex, radix: 16) else { return HidigPalette.forest }
        let red = Double((number >> 16) & 0xff) / 255
        let green = Double((number >> 8) & 0xff) / 255
        let blue = Double(number & 0xff) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance < 0.48 ? Color.white.opacity(0.92) : Color(hex: "#173B2A")
    }

    static func tintNSColor(preference: SidebarColorPreference?, customHex: String) -> NSColor {
        NSColor(hex: preference?.hex ?? customHex)
    }

    static func accentNSColor(preference: SidebarColorPreference?, customHex: String) -> NSColor {
        if let preference {
            return NSColor(hex: preference.accentHex)
        }

        let custom = NSColor(hex: customHex)
        guard let rgb = custom.usingColorSpace(.deviceRGB) else { return NSColor(hex: "#507E4B") }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        let blackFraction = luminance > 0.66 ? 0.44 : (luminance > 0.46 ? 0.25 : 0.08)
        return rgb.blended(withFraction: blackFraction, of: .black) ?? rgb
    }

    static func currentColors() -> (tint: NSColor, accent: NSColor) {
        let defaults = UserDefaults.standard
        let preference = defaults.string(forKey: HidigSettingsKeys.sidebarColor)
            .flatMap(SidebarColorPreference.init(rawValue:))
        let customHex = defaults.string(forKey: HidigSettingsKeys.customSidebarColor) ?? "#E5EFDA"
        return (
            tintNSColor(preference: preference, customHex: customHex),
            accentNSColor(preference: preference, customHex: customHex)
        )
    }

    static func currentTheme(for appearance: NSAppearance) -> HidigThemeColors {
        let preference = UserDefaults.standard.string(forKey: HidigSettingsKeys.sidebarColor)
            .flatMap(SidebarColorPreference.init(rawValue:)) ?? .sage
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return preference.theme(isDark: isDark)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(value, radix: 16) ?? 0
        self.init(
            red: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: 1
        )
    }
}
