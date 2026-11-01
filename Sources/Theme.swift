import AppKit
import SwiftUI

enum HidigPalette {
    static var canvas: Color { themed(\.canvas) }
    static var sidebar: Color { themed(\.sidebar) }
    static var surface: Color { themed(\.surface) }
    static var surfaceRaised: Color { themed(\.surfaceRaised) }
    static var line: Color { themed(\.line) }
    static var lettuce: Color { themed(\.accentSoft) }
    static var lettuceStrong: Color { themed(\.accent) }
    static var controlFill: Color { themed(\.accent) }
    static var onAccent: Color { themed(\.onAccent) }
    static var forest: Color { themed(\.text) }
    static var forestMuted: Color { themed(\.secondary) }
    static var secondary: Color { themed(\.secondary) }
    static var warning: Color { adaptive(light: 0xBC492F, dark: 0xEC9877) }
    static var statusActive: Color { adaptive(light: 0x4B9A65, dark: 0x65BD84) }
    static var statusInactive: Color { adaptive(light: 0xD35D47, dark: 0xF0806B) }
    static var hover: Color { themed(\.hover) }
    static var focusRing: Color { themed(\.accent) }
    static var disabledFill: Color { themed(\.disabled) }

    // Dynamic colors remain adaptive, but their providers and parsed components are
    // created once rather than on every card, hover, and layout pass.
    private static let themedColors: [SidebarColorPreference: [KeyPath<HidigThemeColors, String>: Color]] = {
        let paths: [KeyPath<HidigThemeColors, String>] = [
            \.canvas, \.sidebar, \.surface, \.surfaceRaised, \.line, \.accentSoft,
            \.accent, \.text, \.secondary, \.hover, \.disabled, \.onAccent
        ]
        return Dictionary(uniqueKeysWithValues: SidebarColorPreference.allCases.map { preference in
            let light = preference.theme(isDark: false), dark = preference.theme(isDark: true)
            let colors = Dictionary(uniqueKeysWithValues: paths.map { path in
                let lightColor = NSColor(hex: light[keyPath: path])
                let darkColor = NSColor(hex: dark[keyPath: path])
                let color = NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
                }
                return (path, Color(nsColor: color))
            })
            return (preference, colors)
        })
    }()

    private static func themed(_ keyPath: KeyPath<HidigThemeColors, String>) -> Color {
        let preference = HidigRuntime.defaults.string(forKey: HidigSettingsKeys.sidebarColor)
            .flatMap(SidebarColorPreference.init(rawValue:)) ?? .ocean
        return themedColors[preference]![keyPath]!
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return nsColor(match == .darkAqua ? dark : light)
        })
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

struct SectionEyebrow: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let text: String
    var body: some View {
        Text(text)
            .hidigFont(size: 12, weight: .semibold)
            .foregroundStyle(HidigPalette.secondary)
    }
}

struct PageTitle: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .hidigFont(size: 21, weight: .semibold)
                .foregroundStyle(HidigPalette.forest)
            Text(subtitle)
                .hidigFont(size: 12)
                .foregroundStyle(HidigPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SoftPanel<Content: View>: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .foregroundStyle(HidigPalette.forest)
            .background(HidigPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: PrintTokens.panelRadius).stroke(HidigPalette.line.opacity(0.85)))
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.panelRadius))
    }
}

struct HidigMenuOption: Identifiable, Equatable {
    let id: String
    let title: String
    var systemImage: String? = nil
}

/// A shared label for native menus; opening, selection and keyboard behavior stay native.
struct HidigMenuButtonLabel: View {
    let title: String
    let systemImage: String
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).frame(width: 15).accessibilityHidden(true)
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).accessibilityHidden(true)
        }
        .hidigFont(size: 13, weight: .semibold)
        .foregroundStyle(isActive ? HidigPalette.controlFill : HidigPalette.forest)
        .padding(.horizontal, 12)
        .frame(height: PrintTokens.buttonHeight)
        .background(isHovered ? HidigPalette.hover : HidigPalette.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: PrintTokens.controlRadius).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius))
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.58)
        .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct HidigMenuPicker: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let options: [HidigMenuOption]
    @Binding var selection: String
    var leadingIcon: String? = nil
    var maxListHeight: CGFloat = 280
    var compact = false
    @State private var isPresented = false

    private var selected: HidigMenuOption? {
        options.first { $0.id == selection }
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 8) {
                if let icon = leadingIcon ?? selected?.systemImage {
                    Image(systemName: icon).frame(width: 15)
                }
                Text(selected?.title ?? "Выбрать")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(HidigPalette.secondary)
            }
            .hidigFont(size: compact ? 12 : 13, weight: compact ? .regular : .semibold)
            .padding(.horizontal, compact ? 6 : 11)
            .frame(minHeight: compact ? 28 : PrintTokens.buttonHeight)
            .background(compact ? Color.clear : HidigPalette.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: PrintTokens.controlRadius).stroke(compact ? Color.clear : HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(options) { option in
                        Button {
                            selection = option.id
                            isPresented = false
                        } label: {
                            HStack(spacing: 9) {
                                if let icon = option.systemImage {
                                    Image(systemName: icon).frame(width: 16)
                                }
                                Text(option.title).lineLimit(1)
                                Spacer(minLength: 12)
                                if option.id == selection {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(HidigPalette.controlFill)
                                }
                            }
                            .hidigFont(size: 12, weight: option.id == selection ? .semibold : .regular)
                            .padding(.horizontal, 11)
                            .frame(height: 36)
                            .background(option.id == selection ? HidigPalette.lettuce.opacity(0.55) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
            }
            .frame(minWidth: 210, maxHeight: maxListHeight)
            .background(HidigPalette.surface)
        }
    }
}

struct HidigDateButton: View {
    @Binding var date: Date
    var compact = false
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                Text(date.formatted(.dateTime.day().month(.twoDigits).year()))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .hidigFont(size: compact ? 12 : 13, weight: compact ? .medium : .semibold)
            .padding(.horizontal, 10)
            .frame(height: compact ? 28 : PrintTokens.buttonHeight)
            .background(compact ? HidigPalette.hover.opacity(0.45) : HidigPalette.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: PrintTokens.controlRadius).stroke(compact ? Color.clear : HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            DatePicker("Дата", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
                .frame(width: 280)
                .background(HidigPalette.surface)
        }
    }
}

struct HidigTimeButton: View {
    @Binding var date: Date
    var stepMinutes = 30
    var compact = false
    var timeZoneID: String?
    private var calendar: Calendar {
        var value = PlannerCalendar.current
        if let timeZoneID, let zone = TimeZone(identifier: timeZoneID) { value.timeZone = zone }
        return value
    }
    @State private var isPresented = false

    @State private var exactTime = ""
    @State private var invalidTime = false
    private var selectedMinute: Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: "clock")
                Text(PlannerCalendar.time(date, in: calendar.timeZone))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .hidigFont(size: compact ? 12 : 13, weight: compact ? .medium : .semibold)
            .padding(.horizontal, 10)
            .frame(height: compact ? 28 : PrintTokens.buttonHeight)
            .background(compact ? HidigPalette.hover.opacity(0.45) : HidigPalette.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: PrintTokens.controlRadius).stroke(compact ? Color.clear : HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("ЧЧ:ММ", text: $exactTime)
                        .textFieldStyle(HidigTextFieldStyle())
                        .onSubmit(applyExactTime)
                        .accessibilityLabel("Точное время, часы и минуты")
                    Button(action: applyExactTime) { Image(systemName: "checkmark") }
                        .buttonStyle(.plain).help("Применить время")
                }.padding(.horizontal, 10).padding(.top, 10)
                if invalidTime { Text("Введите время от 00:00 до 23:59").font(.caption).foregroundStyle(HidigPalette.warning) }
                ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(stride(from: 0, to: 24 * 60, by: stepMinutes)), id: \.self) { minute in
                            Button {
                                setMinute(minute)
                                isPresented = false
                            } label: {
                                HStack {
                                    Text(timeLabel(minute))
                                    Spacer()
                                    if selectedMinute == minute {
                                        Image(systemName: "checkmark").foregroundStyle(HidigPalette.controlFill)
                                    }
                                }
                                .hidigFont(size: 12, weight: selectedMinute == minute ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .frame(height: 35)
                                .background(selectedMinute == minute ? HidigPalette.lettuce.opacity(0.55) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(minute)
                        }
                    }
                    .padding(7)
                }
                .frame(width: 190, height: 270)
                .background(HidigPalette.surface)
                .onAppear { reader.scrollTo((selectedMinute / stepMinutes) * stepMinutes, anchor: .center) }
                }
            }.frame(width: 210).background(HidigPalette.surface)
                .onAppear { exactTime = String(format: "%02d:%02d", selectedMinute / 60, selectedMinute % 60); invalidTime = false }
        }
    }

    private func applyExactTime() {
        guard let minute = PlannerTimeInput.minutes(exactTime) else { invalidTime = true; return }
        setMinute(minute); isPresented = false
    }

    private func setMinute(_ minute: Int) {
        date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date) ?? date
    }

    private func timeLabel(_ minute: Int) -> String {
        let value = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return PlannerCalendar.time(value, in: calendar.timeZone)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var expands = false
    func makeBody(configuration: Configuration) -> some View {
        HidigButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: .primary, expands: expands
        )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var expands = false
    func makeBody(configuration: Configuration) -> some View {
        HidigButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: .secondary, expands: expands
        )
    }
}

struct GhostButtonStyle: ButtonStyle {
    var expands = false
    func makeBody(configuration: Configuration) -> some View {
        HidigButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: .ghost, expands: expands
        )
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    var expands = false
    func makeBody(configuration: Configuration) -> some View {
        HidigButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: .destructive, expands: expands
        )
    }
}

struct HidigIconButtonStyle: ButtonStyle {
    var isDestructive = false
    var foreground: Color? = nil
    var hoverFill: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        HidigIconButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isDestructive: isDestructive, foreground: foreground, hoverFill: hoverFill
        )
    }
}

struct SelectionRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SelectionRowButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isSelected
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Выбрано" : "Не выбрано")
    }
}

private struct SelectionRowButtonBody<Label: View>: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let isSelected: Bool

    var body: some View {
        label
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: PrintTokens.controlRadius, style: .continuous)
                    .stroke(isSelected ? HidigPalette.focusRing : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(isPressed && !reduceMotion ? 0.992 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isPressed)
            .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected { return HidigPalette.surfaceRaised }
        if isHovered || isPressed { return HidigPalette.hover.opacity(0.72) }
        return .clear
    }
}

private struct HidigIconButtonBody<Label: View>: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let isDestructive: Bool
    let foreground: Color?
    let hoverFill: Color?

    var body: some View {
        label
            .hidigFont(size: 13, weight: .semibold)
            .foregroundStyle(isDestructive ? HidigPalette.warning : (foreground ?? HidigPalette.forest))
            .frame(width: PrintTokens.buttonHeight, height: PrintTokens.buttonHeight)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: PrintTokens.controlRadius, style: .continuous)
                    .stroke(isHovered ? border : .clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isPressed)
            .onHover { isHovered = $0 }
    }

    private var background: Color {
        guard isHovered || isPressed else { return .clear }
        return isDestructive ? HidigPalette.warning.opacity(0.12) : (hoverFill ?? HidigPalette.hover)
    }

    private var border: Color {
        isDestructive ? HidigPalette.warning.opacity(0.45) : (foreground?.opacity(0.2) ?? HidigPalette.line)
    }
}

private enum HidigButtonKind {
    case primary
    case secondary
    case ghost
    case destructive
}

private struct HidigButtonBody<Label: View>: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let kind: HidigButtonKind
    let expands: Bool

    var body: some View {
        label
            .hidigFont(size: 13, weight: .semibold)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minWidth: 64, maxWidth: expands ? .infinity : nil, minHeight: PrintTokens.buttonHeight)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: PrintTokens.controlRadius, style: .continuous)
                    .stroke(border, lineWidth: kind == .ghost ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius, style: .continuous))
            .scaleEffect(isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.58)
            .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        if !isEnabled { return HidigPalette.secondary }
        switch kind {
        case .primary:
            return HidigPalette.onAccent
        case .secondary, .ghost:
            return HidigPalette.forest
        case .destructive:
            return HidigPalette.warning
        }
    }

    private var background: Color {
        guard isEnabled else { return HidigPalette.disabledFill }
        switch kind {
        case .primary:
            return HidigPalette.controlFill
        case .secondary:
            if isPressed { return HidigPalette.lettuce.opacity(0.5) }
            return isHovered ? HidigPalette.hover : HidigPalette.surfaceRaised
        case .ghost:
            return isHovered || isPressed ? HidigPalette.hover : .clear
        case .destructive:
            return isHovered || isPressed ? HidigPalette.warning.opacity(0.12) : HidigPalette.surfaceRaised
        }
    }

    private var border: Color {
        switch kind {
        case .primary:
            return HidigPalette.controlFill
        case .secondary:
            return isHovered ? HidigPalette.focusRing : HidigPalette.line
        case .ghost:
            return .clear
        case .destructive:
            return HidigPalette.warning.opacity(isHovered ? 0.75 : 0.38)
        }
    }
}

struct HidigCheckmarkBox: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let isChecked: Bool
    var isEnabled = true
    var isHovered = false
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "checkmark")
            .hidigFont(size: size * 0.42, weight: .bold)
            .foregroundStyle(HidigPalette.onAccent)
            .opacity(isChecked ? 1 : 0)
            .frame(width: size, height: size)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: max(4, size * 0.25), style: .continuous)
                    .stroke(border, lineWidth: isHovered ? 1.8 : 1.45)
            )
            .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.25), style: .continuous))
            .opacity(isEnabled || isChecked ? 1 : 0.72)
            .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isChecked)
            .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isHovered)
    }

    private var background: Color {
        if isChecked { return HidigPalette.controlFill }
        return isHovered && isEnabled ? HidigPalette.hover : .clear
    }

    private var border: Color {
        if isChecked { return HidigPalette.controlFill }
        return isHovered && isEnabled ? HidigPalette.focusRing : HidigPalette.secondary.opacity(0.6)
    }
}

struct HidigCheckboxRow: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let title: String
    let isOn: Bool
    let action: () -> Void
    var isEnabled = true

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                HidigCheckmarkBox(
                    isChecked: isOn,
                    isEnabled: isEnabled,
                    isHovered: isHovered,
                    size: 22
                )
                Text(title)
                    .hidigFont(size: 13, weight: .medium)
                    .foregroundStyle(HidigPalette.forest)
                    .lineLimit(2)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(isHovered && isEnabled ? HidigPalette.hover.opacity(0.72) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }
}

struct HidigTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .hidigFont(size: 14)
            .foregroundStyle(HidigPalette.forest)
            .tint(HidigPalette.lettuceStrong)
            .padding(.horizontal, 13)
            .frame(height: PrintTokens.inputHeight)
            .background(HidigPalette.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: PrintTokens.controlRadius).stroke(HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.controlRadius))
    }
}

struct StatusDot: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let isActive: Bool
    var body: some View {
        Circle()
            .fill(isActive ? HidigPalette.statusActive : HidigPalette.statusInactive)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}
