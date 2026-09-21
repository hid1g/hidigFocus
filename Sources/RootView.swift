import SwiftUI

struct RootView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @AppStorage(HidigSettingsKeys.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(HidigSettingsKeys.sidebarColor) private var sidebarColorRaw = SidebarColorPreference.ocean.rawValue
    @AppStorage(HidigSettingsKeys.customSidebarColor) private var customSidebarColorHex = "#E5EFDA"
    @State private var showsDisableProtection = false
    @AppStorage("navigationCollapsed") private var navigationCollapsed = true
    @AppStorage("navigationWidth") private var navigationWidth = 240.0

    private var resolvedNavigationWidth: Double {
        min(320, max(224, navigationWidth))
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                showsDisableProtection: $showsDisableProtection,
                isCollapsed: $navigationCollapsed,
                backgroundColor: HidigPalette.sidebar,
                foregroundColor: HidigPalette.forest
            )
                .frame(width: navigationCollapsed ? 64 : resolvedNavigationWidth)
            if !navigationCollapsed {
                PanelResizeHandle(width: $navigationWidth, bounds: 224...320)
            }

            Group {
                switch store.selectedSection {
                case .today: TodayView()
                case .tasks: TasksView()
                case .groups: GroupsView()
                case .habits: HabitsView()
                case .statistics: StatisticsView()
                case .tickTick: TickTickView()
                case .journal: JournalView()
                case .settings: SettingsView()
                }
            }
            .id(store.selectedSection)
            .transition(.opacity.combined(with: .scale(scale: 0.995)))
            .animation(.easeInOut(duration: 0.22), value: store.selectedSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HidigPalette.canvas)
        }
        .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.88), value: navigationCollapsed)
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
        .onAppear {
            navigationWidth = resolvedNavigationWidth
        }
    }

}

private struct Sidebar: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @Binding var showsDisableProtection: Bool
    @Binding var isCollapsed: Bool
    let backgroundColor: Color
    let foregroundColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                AppIconPreview(style: .green, size: 38)
                if !isCollapsed { VStack(alignment: .leading, spacing: 1) {
                    Text("hidigFocus")
                        .hidigFont(size: 17, weight: .semibold, design: .rounded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("focus gate")
                        .hidigFont(size: 10, weight: .medium, design: .rounded)
                        .tracking(1)
                        .foregroundStyle(foregroundColor.opacity(0.68))
                }
                .layoutPriority(1)
                .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                if !isCollapsed {
                    Spacer(minLength: 4)
                    collapseButton
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, isCollapsed ? 13 : 20)

            VStack(spacing: 5) {
                ForEach(AppSection.allCases) { section in
                    SidebarButton(section: section, foregroundColor: foregroundColor, isCollapsed: isCollapsed)
                }
            }
            .padding(.horizontal, isCollapsed ? 8 : 12)
            .padding(.top, isCollapsed ? 52 : 22)

            Spacer()

            if isCollapsed {
                Button {
                    if store.protectionEnabled { showsDisableProtection = true }
                    else { store.setProtectionEnabled(true) }
                } label: {
                    Image(systemName: store.protectionEnabled ? "lock.shield.fill" : "lock.open")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain)
                    .help(store.protectionEnabled ? "Защита включена" : "Включить защиту")
                    .padding(.bottom, 14)
            } else { VStack(alignment: .leading, spacing: 11) {
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
        }
        .foregroundStyle(foregroundColor)
        .background(backgroundColor)
        .overlay(alignment: .trailing) {
            Rectangle().fill(HidigPalette.line).frame(width: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isCollapsed {
                collapseButton
                    .padding(.top, 98)
                    .padding(.trailing, 6)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.3,
                          abs(value.translation.width) > 44 else { return }
                    if isCollapsed && value.translation.width > 0 {
                        setCollapsed(false)
                    } else if !isCollapsed && value.translation.width < 0 {
                        setCollapsed(true)
                    }
                }
        )
        .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.88), value: isCollapsed)
    }

    private var collapseButton: some View {
        Button {
            setCollapsed(!isCollapsed)
        } label: {
            Image(systemName: isCollapsed ? "sidebar.right" : "sidebar.left")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(backgroundColor.opacity(0.92))
                .overlay(Circle().stroke(foregroundColor.opacity(0.22)))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Развернуть навигацию" : "Свернуть навигацию")
        .accessibilityLabel(isCollapsed ? "Развернуть навигацию" : "Свернуть навигацию")
    }

    private func setCollapsed(_ value: Bool) {
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88)) {
            isCollapsed = value
        }
    }
}

private struct SidebarButton: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let section: AppSection
    let foregroundColor: Color
    let isCollapsed: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { store.selectedSection = section }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.systemImage).frame(width: 18)
                if !isCollapsed {
                    Text(section.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                    Spacer()
                }
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
        .help(section.title)
        .accessibilityLabel(section.title)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: store.selectedSection)
    }

    private var background: Color {
        if store.selectedSection == section { return Color.white.opacity(0.2) }
        return isHovered ? Color.white.opacity(0.12) : .clear
    }
}

struct PanelResizeHandle: View {
    @Binding var width: Double
    var bounds: ClosedRange<Double>
    @State private var initialWidth: Double?
    var body: some View {
        Rectangle().fill(HidigPalette.line.opacity(0.5)).frame(width: 5)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                if initialWidth == nil { initialWidth = width }
                width = min(bounds.upperBound, max(bounds.lowerBound, (initialWidth ?? width) + value.translation.width))
            }.onEnded { _ in initialWidth = nil })
            .onHover { inside in (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set() }
            .onDisappear { NSCursor.arrow.set() }
            .accessibilityLabel("Изменить ширину панели")
    }
}

private struct DisableProtectionSheet: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionEyebrow(text: "Необратимое действие")
            Text("Отключить защиту?")
                .hidigFont(size: 28, weight: .bold, design: .rounded)
                .foregroundStyle(HidigPalette.forest)
            Text(disableWarning)
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

    private var disableWarning: String {
        let streak = RussianPluralizer.phrase(
            store.disciplineStreak,
            one: "день",
            few: "дня",
            many: "дней"
        )
        return "Ваша серия — \(streak) без отключения защиты — будет потеряна. Группы откроются, а текущие серии всех привычек обнулятся. Сами привычки и история отметок сохранятся."
    }
}
