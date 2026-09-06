import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(HidigSettingsKeys.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(HidigSettingsKeys.sidebarColor) private var sidebarColorRaw = SidebarColorPreference.sage.rawValue
    @AppStorage(HidigSettingsKeys.customSidebarColor) private var customSidebarColorHex = "#E5EFDA"
    @State private var showsDisableProtection = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                showsDisableProtection: $showsDisableProtection,
                backgroundColor: HidigPalette.sidebar,
                foregroundColor: HidigPalette.forest
            )
                .frame(width: 226)

            Group {
                switch store.selectedSection {
                case .today: TodayView()
                case .groups: GroupsView()
                case .habits: HabitsView()
                case .statistics: StatisticsView()
                case .tickTick: TickTickView()
                case .journal: JournalView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HidigPalette.canvas)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showsDisableProtection) {
            DisableProtectionSheet(isPresented: $showsDisableProtection)
                .environmentObject(store)
        }
        .alert(
            "hidigFocus",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("Закрыть", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .tint(HidigPalette.forest)
        .foregroundStyle(HidigPalette.forest)
        .preferredColorScheme(AppearancePreference(rawValue: appearanceRaw)?.colorScheme)
        .onChange(of: appearanceRaw) { value in
            AppAppearanceController.apply(AppearancePreference(rawValue: value) ?? .system)
        }
    }

}

private struct Sidebar: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showsDisableProtection: Bool
    let backgroundColor: Color
    let foregroundColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "leaf.fill")
                    .hidigFont(size: 19, weight: .semibold)
                    .foregroundStyle(foregroundColor)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("hidigFocus")
                        .hidigFont(size: 17, weight: .semibold, design: .rounded)
                    Text("focus gate")
                        .hidigFont(size: 10, weight: .medium, design: .rounded)
                        .tracking(1)
                        .foregroundStyle(foregroundColor.opacity(0.68))
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 20)

            VStack(spacing: 5) {
                ForEach(AppSection.allCases) { section in
                    SidebarButton(section: section, foregroundColor: foregroundColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 35)

            Spacer()

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    StatusDot(isActive: store.protectionEnabled)
                    Text(store.protectionEnabled ? "Защита включена" : "Защита выключена")
                        .hidigFont(size: 12, weight: .semibold)
                }
                Text(store.protectionEnabled
                     ? "Закрытые группы откроются после выполнения назначенных задач."
                     : "Сайты и приложения сейчас доступны.")
                    .hidigFont(size: 11)
                    .foregroundStyle(foregroundColor.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                Button(store.protectionEnabled ? "Отключить защиту" : "Включить защиту") {
                    if store.protectionEnabled {
                        showsDisableProtection = true
                    } else {
                        store.setProtectionEnabled(true)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
            .background(Color.white.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(14)
            .padding(.bottom, 8)
        }
        .foregroundStyle(foregroundColor)
        .background(backgroundColor)
        .overlay(alignment: .trailing) {
            Rectangle().fill(HidigPalette.line).frame(width: 1)
        }
    }
}

private struct SidebarButton: View {
    @EnvironmentObject private var store: AppStore
    let section: AppSection
    let foregroundColor: Color
    @State private var isHovered = false

    var body: some View {
        Button {
            store.selectedSection = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.systemImage).frame(width: 18)
                Text(section.title)
                Spacer()
            }
            .contentShape(Rectangle())
            .hidigFont(size: 13, weight: store.selectedSection == section ? .semibold : .regular)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if store.selectedSection == section { return Color.white.opacity(0.2) }
        return isHovered ? Color.white.opacity(0.12) : .clear
    }
}

private struct DisableProtectionSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionEyebrow(text: "Необратимое действие")
            Text("Отключить защиту?")
                .hidigFont(size: 28, weight: .bold, design: .rounded)
                .foregroundStyle(HidigPalette.forest)
            Text("Группы будут открыты. Текущая серия дисциплины и текущие серии всех привычек станут равны нулю. Сами привычки и история отметок сохранятся.")
                .foregroundStyle(HidigPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Введите ОТКЛЮЧИТЬ")
                .hidigFont(size: 12, weight: .semibold)
            TextField("ОТКЛЮЧИТЬ", text: $confirmation)
                .textFieldStyle(HidigTextFieldStyle())
            HStack {
                Button("Отмена") { isPresented = false }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Обнулить серии и отключить") {
                    store.disableProtection()
                    isPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(confirmation != "ОТКЛЮЧИТЬ")
            }
        }
        .padding(30)
        .frame(width: 480)
        .background(HidigPalette.canvas)
    }
}
