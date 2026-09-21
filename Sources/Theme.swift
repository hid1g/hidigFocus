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
    static var forest: Color { themed(\.text) }
    static var forestMuted: Color { themed(\.secondary) }
    static var secondary: Color { themed(\.secondary) }
    static var warning: Color { adaptive(light: 0x9A4E3A, dark: 0xE49A83) }
    static var hover: Color { themed(\.hover) }
    static var focusRing: Color { themed(\.accent) }
    static var disabledFill: Color { themed(\.disabled) }

    private static func themed(_ keyPath: KeyPath<HidigThemeColors, String>) -> Color {
        let preference = UserDefaults.standard.string(forKey: HidigSettingsKeys.sidebarColor)
            .flatMap(SidebarColorPreference.init(rawValue:)) ?? .ocean
        return Color(nsColor: NSColor(name: NSColor.Name("\(preference.rawValue)-\(keyPath)")) { appearance in
            let colors = preference.theme(isDark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            return NSColor(hex: colors[keyPath: keyPath])
        })
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
        Text(text.uppercased())
            .hidigFont(size: 11, weight: .bold, design: .rounded)
            .tracking(1.25)
            .foregroundStyle(HidigPalette.secondary)
    }
}

struct PageTitle: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionEyebrow(text: eyebrow)
            Text(title)
                .hidigFont(size: 34, weight: .bold, design: .rounded)
                .foregroundStyle(HidigPalette.forest)
            Text(subtitle)
                .hidigFont(size: 14)
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
            .padding(20)
            .foregroundStyle(HidigPalette.forest)
            .background(HidigPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HidigPalette.line.opacity(0.85)))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct HidigMenuOption: Identifiable, Equatable {
    let id: String
    let title: String
    var systemImage: String? = nil
}

struct HidigMenuPicker: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let options: [HidigMenuOption]
    @Binding var selection: String
    var leadingIcon: String? = nil
    var maxListHeight: CGFloat = 280
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
            .hidigFont(size: 11, weight: .semibold)
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(HidigPalette.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 9))
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
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                Text(date.formatted(.dateTime.day().month(.twoDigits).year()))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .hidigFont(size: 11, weight: .semibold)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(HidigPalette.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 9))
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
    @State private var isPresented = false

    private var selectedMinute: Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: "clock")
                Text(date.formatted(date: .omitted, time: .shortened))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .hidigFont(size: 11, weight: .semibold)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(HidigPalette.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
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
                                    if abs(selectedMinute - minute) < stepMinutes {
                                        Image(systemName: "checkmark").foregroundStyle(HidigPalette.controlFill)
                                    }
                                }
                                .hidigFont(size: 12, weight: abs(selectedMinute - minute) < stepMinutes ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .frame(height: 35)
                                .background(abs(selectedMinute - minute) < stepMinutes ? HidigPalette.lettuce.opacity(0.55) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(minute)
                        }
                    }
                    .padding(7)
                }
                .frame(width: 160, height: 270)
                .background(HidigPalette.surface)
                .onAppear {
                    reader.scrollTo((selectedMinute / stepMinutes) * stepMinutes, anchor: .center)
                }
            }
        }
    }

    private func setMinute(_ minute: Int) {
        date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date) ?? date
    }

    private func timeLabel(_ minute: Int) -> String {
        let value = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return value.formatted(date: .omitted, time: .shortened)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HidigButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: .primary
        )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HidigButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: .secondary
        )
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HidigButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: .ghost
        )
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HidigButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: .destructive
        )
    }
}

struct HidigIconButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        HidigIconButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isDestructive: isDestructive
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
    }
}

private struct SelectionRowButtonBody<Label: View>: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let isSelected: Bool

    var body: some View {
        label
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? HidigPalette.focusRing : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected { return HidigPalette.surfaceRaised }
        if isHovered || isPressed { return HidigPalette.hover.opacity(0.72) }
        return .clear
    }
}

private struct HidigIconButtonBody<Label: View>: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let isDestructive: Bool

    var body: some View {
        label
            .hidigFont(size: 13, weight: .semibold)
            .foregroundStyle(isDestructive ? HidigPalette.warning : HidigPalette.forest)
            .frame(width: 32, height: 32)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isHovered ? border : .clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .onHover { isHovered = $0 }
    }

    private var background: Color {
        guard isHovered || isPressed else { return .clear }
        return isDestructive ? HidigPalette.warning.opacity(0.12) : HidigPalette.hover
    }

    private var border: Color {
        isDestructive ? HidigPalette.warning.opacity(0.45) : HidigPalette.line
    }
}

private enum HidigButtonKind {
    case primary
    case secondary
    case ghost
    case destructive
}

private struct HidigButtonBody<Label: View>: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let kind: HidigButtonKind

    var body: some View {
        label
            .hidigFont(size: 13, weight: .semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, 15)
            .frame(minHeight: 38)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(border, lineWidth: kind == .ghost ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.58)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            return .white
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
            if isPressed { return HidigPalette.controlFill.opacity(0.78) }
            return isHovered ? HidigPalette.controlFill.opacity(0.88) : HidigPalette.controlFill
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
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let isChecked: Bool
    var isEnabled = true
    var isHovered = false
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "checkmark")
            .hidigFont(size: size * 0.42, weight: .bold)
            .foregroundStyle(Color.white)
            .opacity(isChecked ? 1 : 0)
            .frame(width: size, height: size)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: max(6, size * 0.28), style: .continuous)
                    .stroke(border, lineWidth: isHovered ? 1.8 : 1.45)
            )
            .clipShape(RoundedRectangle(cornerRadius: max(6, size * 0.28), style: .continuous))
            .opacity(isEnabled || isChecked ? 1 : 0.72)
            .animation(.easeOut(duration: 0.12), value: isChecked)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var background: Color {
        if isChecked { return HidigPalette.controlFill }
        return isHovered && isEnabled ? HidigPalette.hover : HidigPalette.surfaceRaised
    }

    private var border: Color {
        if isChecked { return HidigPalette.controlFill }
        return isHovered && isEnabled ? HidigPalette.focusRing : HidigPalette.line
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
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(isHovered && isEnabled ? HidigPalette.hover.opacity(0.72) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
            .frame(height: 38)
            .background(HidigPalette.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StatusDot: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let isActive: Bool
    var body: some View {
        Circle()
            .fill(isActive ? HidigPalette.lettuceStrong : HidigPalette.warning)
            .frame(width: 8, height: 8)
    }
}
