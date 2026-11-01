import SwiftUI

struct RootView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @AppStorage(HidigSettingsKeys.appearance, store: HidigRuntime.defaults) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(HidigSettingsKeys.sidebarColor, store: HidigRuntime.defaults) private var sidebarColorRaw = SidebarColorPreference.ocean.rawValue
    @AppStorage(HidigSettingsKeys.customSidebarColor, store: HidigRuntime.defaults) private var customSidebarColorHex = "#E5EFDA"
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @State private var showsDisableProtection = false
    @State private var availableWidth: CGFloat = 1440
    @State private var showsCompactNavigation = false
    @AppStorage("navigationCollapsed", store: HidigRuntime.defaults) private var navigationCollapsed = true
    @AppStorage("navigationWidth", store: HidigRuntime.defaults) private var navigationWidth = 194.0
    @State private var navigationDraftWidth = 194.0
    @GestureState private var navigationDragX: CGFloat = 0

    private var resolvedNavigationWidth: Double {
        min(320, max(190, navigationDraftWidth))
    }

    private var displayedNavigationWidth: CGFloat {
        if availableWidth < 1000 { return PrintTokens.compactNavigationWidth }
        let collapsedWidth = PrintTokens.compactNavigationWidth
        let expandedWidth = CGFloat(resolvedNavigationWidth)
        let base = navigationCollapsed ? collapsedWidth : expandedWidth
        let directionalDrag = navigationCollapsed ? max(0, navigationDragX) : min(0, navigationDragX)
        return min(expandedWidth, max(collapsedWidth, base + directionalDrag))
    }

    private var sidebarIsCompact: Bool {
        displayedNavigationWidth < 148
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .onAppear { availableWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { availableWidth = $0 }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            Sidebar(
                showsDisableProtection: $showsDisableProtection,
                isCollapsed: sidebarIsCompact,
                backgroundColor: HidigPalette.sidebar,
                foregroundColor: SidebarColorResolver.foreground(preference: SidebarColorPreference(rawValue: sidebarColorRaw), customHex: customSidebarColorHex),
                onSelect: { showsCompactNavigation = false }
            )
                .frame(width: displayedNavigationWidth)
            if !sidebarIsCompact && navigationDragX == 0 {
                PanelResizeHandle(width: $navigationDraftWidth, bounds: 190...320, onCommit: { navigationWidth = $0 })
            }

            sectionView(store.selectedSection)
            .buttonStyle(SecondaryButtonStyle())
            .environment(\.hidigContentWidth, max(0, availableWidth - displayedNavigationWidth))
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.selectedSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HidigPalette.canvas)
        }
        .disabled(store.dataIsReadOnly)
        .overlay {
            if store.dataIsReadOnly {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Не удалось загрузить данные").hidigFont(size: 20, weight: .semibold)
                    Text("Редактирование и подключения остановлены. Исходная база не изменена. Проверьте доступ к хранилищу и перезапустите приложение.")
                        .hidigFont(size: 13).fixedSize(horizontal: false, vertical: true)
                }.padding(24).frame(maxWidth: 460).background(HidigPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(navigationGesture)
        .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.panel), value: navigationCollapsed)
        .overlay(alignment: .leading) {
            if showsCompactNavigation && availableWidth < 1000 {
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.16).onTapGesture { showsCompactNavigation = false }
                    Sidebar(
                        showsDisableProtection: $showsDisableProtection,
                        isCollapsed: false,
                        backgroundColor: HidigPalette.sidebar,
                        foregroundColor: SidebarColorResolver.foreground(preference: SidebarColorPreference(rawValue: sidebarColorRaw), customHex: customSidebarColorHex),
                        onSelect: { showsCompactNavigation = false }
                    )
                    .frame(width: max(220, resolvedNavigationWidth))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 6, y: 3)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: PrintDesign.panel)) {
                        if availableWidth < 1000 { showsCompactNavigation.toggle() }
                        else { navigationCollapsed.toggle() }
                    }
                } label: { Image(systemName: "sidebar.left") }
                .help("Показать или скрыть навигацию")
                .accessibilityLabel("Показать или скрыть навигацию")
            }
            ToolbarItem(placement: .navigation) { MainWindowToolbarTitle() }
        }
        .toolbarBackground(HidigPalette.canvas, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .onChange(of: availableWidth) { if $0 >= 1000 { showsCompactNavigation = false } }
        .sheet(isPresented: $showsDisableProtection) {
            DisableProtectionSheet(isPresented: $showsDisableProtection)
                .environmentObject(store)
        }
        .sheet(item: $store.pendingProtectedResourceChange) { change in
            ProtectedResourceChangeSheet(change: change).environmentObject(store)
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
        .tint(HidigPalette.controlFill)
        .foregroundStyle(HidigPalette.forest)
        .preferredColorScheme(AppearancePreference(rawValue: appearanceRaw)?.colorScheme)
        .onChange(of: appearanceRaw) { value in
            AppAppearanceController.apply(AppearancePreference(rawValue: value) ?? .system)
        }
        .onAppear {
            navigationDraftWidth = min(320, max(190, navigationWidth))
        }
    }

    @ViewBuilder private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .today: TodayView()
        case .tasks, .calendar: TasksView()
        case .pomodoro: FocusView()
        case .groups: GroupsView()
        case .habits: HabitsView()
        case .statistics: StatisticsView()
        case .tickTick: TickTickView()
        case .journal: JournalView()
        case .settings: SettingsView()
        }
    }

    private var navigationGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($navigationDragX) { value, state, _ in
                guard availableWidth >= 1000 else { return }
                let boundary = navigationCollapsed ? 92 : CGFloat(resolvedNavigationWidth) + 18
                guard value.startLocation.x <= boundary,
                      abs(value.translation.width) > abs(value.translation.height) * 1.15 else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard availableWidth >= 1000 else { return }
                let boundary = navigationCollapsed ? 92 : CGFloat(resolvedNavigationWidth) + 18
                guard value.startLocation.x <= boundary,
                      abs(value.translation.width) > abs(value.translation.height) * 1.15 else { return }
                let projected = value.predictedEndTranslation.width
                if navigationCollapsed, projected > 48 {
                    navigationCollapsed = false
                } else if !navigationCollapsed, projected < -48 {
                    navigationCollapsed = true
                }
            }
    }

}

private struct Sidebar: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @AppStorage(HidigSettingsKeys.appIcon, store: HidigRuntime.defaults) private var appIconRaw = AppIconPreference.green.rawValue
    @Binding var showsDisableProtection: Bool
    let isCollapsed: Bool
    let backgroundColor: Color
    let foregroundColor: Color
    var onSelect: () -> Void
    @Environment(\.hidigReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppIconPreview(style: AppIconPreference(rawValue: appIconRaw) ?? .green, size: 28)
                if !isCollapsed { VStack(alignment: .leading, spacing: 1) {
                    Text("hidigFocus")
                        .hidigFont(size: 15, weight: .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .layoutPriority(1)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
                }
                if !isCollapsed {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, minHeight: PrintTokens.buttonHeight, maxHeight: PrintTokens.buttonHeight)
            .padding(.top, 16)
            .padding(.horizontal, isCollapsed ? 13 : 14)
            VStack(spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    SidebarButton(section: section, foregroundColor: foregroundColor, isCollapsed: isCollapsed, onSelect: onSelect)
                }
            }
            .padding(.horizontal, isCollapsed ? 8 : 12)
            .padding(.top, 24)

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

                Button {
                    if store.protectionEnabled {
                        showsDisableProtection = true
                    } else {
                        store.setProtectionEnabled(true)
                    }
                } label: {
                    Text(store.protectionEnabled ? "Отключить защиту" : "Включить защиту")
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .buttonStyle(SecondaryButtonStyle(expands: true))
            }
            .padding(12)
            .background(foregroundColor.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(14)
            .padding(.bottom, 8)
            }
        }
        .foregroundStyle(foregroundColor)
        .background(backgroundColor)
        .overlay(alignment: .trailing) {
            Rectangle().fill(HidigPalette.line).frame(width: 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.panel), value: isCollapsed)
        .onChange(of: store.selectedSection) { _ in onSelect() }
    }

}

private struct SidebarButton: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let section: AppSection
    let foregroundColor: Color
    let isCollapsed: Bool
    var onSelect: () -> Void = {}
    @State private var isHovered = false

    var body: some View {
        Button {
            // Both destinations share one planner; changing them must not animate its layout.
            var transaction = Transaction()
            transaction.disablesAnimations = section == .tasks || section == .calendar
            withTransaction(transaction) {
                if section == .tasks { store.planner.presentation = .list }
                if section == .calendar { store.planner.presentation = .calendar }
                store.selectedSection = section
            }
            onSelect()
        } label: {
            Group {
                if isCollapsed {
                    VStack(spacing: 4) {
                        HidigNavigationIcon(section: section)

                    }
                } else {
                    HStack(spacing: 10) {
                        HidigNavigationIcon(section: section)
                        Text(section.title).lineLimit(1)
                        Spacer(minLength: 0)
                    }.hidigFont(size: 13, weight: store.selectedSection == section ? .semibold : .regular)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, isCollapsed ? 2 : 10)
            .frame(maxWidth: .infinity, minHeight: isCollapsed ? 36 : 36)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(store.selectedSection == section ? .isSelected : [])
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.state), value: store.selectedSection)
    }

    private var background: Color {
        if store.selectedSection == section { return foregroundColor.opacity(0.16) }
        return isHovered ? foregroundColor.opacity(0.08) : .clear
    }
}

struct PanelResizeHandle: View {
    @Binding var width: Double
    var bounds: ClosedRange<Double>
    var onCommit: ((Double) -> Void)? = nil
    @State private var initialWidth: Double?
    var body: some View {
        Rectangle().fill(HidigPalette.line.opacity(0.5)).frame(width: 5)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                if initialWidth == nil { initialWidth = width }
                width = min(bounds.upperBound, max(bounds.lowerBound, (initialWidth ?? width) + value.translation.width))
            }.onEnded { _ in
                onCommit?(width)
                initialWidth = nil
            })
            .onHover { inside in (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set() }
            .onDisappear { NSCursor.arrow.set() }
            .accessibilityLabel("Изменить ширину панели")
    }
}

private struct ProtectedResourceChangeSheet: View {
    @EnvironmentObject private var store: AppStore
    let change: ProtectedResourceChange
    @State private var confirmation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionEyebrow(text: "Необратимое действие")
            Text(change.title).hidigFont(size: 28, weight: .bold, design: .rounded)
            Text(warning)
                .foregroundStyle(HidigPalette.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Введите \(change.confirmationWord)").hidigFont(size: 12, weight: .semibold)
            TextField(change.confirmationWord, text: $confirmation).textFieldStyle(HidigTextFieldStyle())
            HStack {
                Button("Отмена") { store.pendingProtectedResourceChange = nil }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(change.confirmationButtonTitle) {
                    do { _ = try store.confirmProtectedResourceChange(confirmation) }
                    catch { store.errorMessage = error.localizedDescription }
                }.buttonStyle(PrimaryButtonStyle()).disabled(confirmation != change.confirmationWord)
            }
        }.padding(30).frame(width: 480).foregroundStyle(HidigPalette.forest).background(HidigPalette.canvas)
    }
    private var warning: String {
        let streak = RussianPluralizer.phrase(store.disciplineStreak, one: "день", few: "дня", many: "дней")
        if case .disableGroup = change.operation {
            let name = store.appliedGroup(change.groupID)?.name ?? ""
            return "Ваша серия — \(streak) без отключения защиты — будет потеряна. Правило «\(name)» станет неактивным, его сайты и приложения откроются, а текущие серии всех привычек обнулятся. Остальные правила продолжат действовать. Сами привычки и история отметок сохранятся."
        }
        return "Серия защиты — \(streak) — и текущие серии привычек обнулятся. Состояние защиты не изменится. Привычки и история отметок сохранятся."
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
