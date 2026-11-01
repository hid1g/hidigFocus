import SwiftUI

struct SettingsView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var journal: JournalState
    @EnvironmentObject private var integration: IntegrationState
    @EnvironmentObject private var store: AppStore

    @AppStorage(HidigSettingsKeys.appearance, store: HidigRuntime.defaults) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(HidigSettingsKeys.font, store: HidigRuntime.defaults) private var fontRaw = HidigFontPreference.system.rawValue
    @AppStorage(HidigSettingsKeys.textSize, store: HidigRuntime.defaults) private var textSizeRaw = HidigTextSizePreference.standard.rawValue
    @AppStorage(HidigSettingsKeys.sidebarColor, store: HidigRuntime.defaults) private var sidebarColorRaw = SidebarColorPreference.ocean.rawValue
    @AppStorage(HidigSettingsKeys.customSidebarColor, store: HidigRuntime.defaults) private var customSidebarColorHex = "#E5EFDA"
    @AppStorage(HidigSettingsKeys.appIcon, store: HidigRuntime.defaults) private var appIconRaw = AppIconPreference.green.rawValue
    @AppStorage(HidigSettingsKeys.showDockIcon, store: HidigRuntime.defaults) private var showDockIcon = true
    @AppStorage(HidigSettingsKeys.openWindowOnLaunch, store: HidigRuntime.defaults) private var openWindowOnLaunch = true

    @AppStorage("planner.firstWeekday", store: HidigRuntime.defaults) private var plannerWeekday = 2
    @AppStorage("planner.use24Hours", store: HidigRuntime.defaults) private var planner24Hours = true
    @AppStorage("planner.timeZone", store: HidigRuntime.defaults) private var plannerZone = ""
    @State private var launchAtLogin = false
    @State private var showsBrowserHelp = false

    @AppStorage("settings.category", store: HidigRuntime.defaults) private var category = "Оформление"
    @AppStorage(PrintDesign.iconPackKey, store: HidigRuntime.defaults) private var iconPackRaw = "duotone"
    @AppStorage("calendarHourHeight", store: HidigRuntime.defaults) private var calendarHourHeight = 96.0
    private let categories = ["Оформление", "Календарь", "Приложение", "Импорт", "Браузер", "Журнал"]

    private let threeColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageTitle(
                    eyebrow: "Управление приложением",
                    title: "Настройки",
                    subtitle: "Оформление, запуск, интеграции и расположение локальных данных."
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(categories, id: \.self) { item in
                            Button { category = item } label: {
                                Text(item).hidigFont(size: 12, weight: category == item ? .semibold : .regular)
                                    .foregroundStyle(category == item ? HidigPalette.forest : HidigPalette.secondary)
                                    .padding(.vertical, 12)
                                    .overlay(alignment: .bottom) { Rectangle().fill(category == item ? HidigPalette.controlFill : .clear).frame(height: 2) }
                            }.buttonStyle(.plain).accessibilityAddTraits(category == item ? .isSelected : [])
                        }
                    }
                }.overlay(alignment: .bottom) { Rectangle().fill(HidigPalette.line).frame(height: 1) }


                switch category {
                case "Оформление": appearanceSection
                case "Календарь": calendarSection
                case "Приложение": applicationSection
                case "Импорт": tickTickSection
                case "Браузер": browserSection
                default: journalSection
                }

            }
            .padding(.horizontal, 22)
            .padding(.vertical, 30)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: plannerWeekday) { _ in store.prepareCalendarIndex(force: true) }
            .onChange(of: plannerZone) { _ in store.prepareCalendarIndex(force: true) }
            .onChange(of: planner24Hours) { _ in store.planner.calendarRevision += 1 }
        }
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.canvas)
        .preferredColorScheme(AppearancePreference(rawValue: appearanceRaw)?.colorScheme)
        .onAppear {
            launchAtLogin = LaunchAtLoginController.isEnabled
            AppAppearanceController.apply(AppearancePreference(rawValue: appearanceRaw) ?? .system)
            if let current = AppIconPreference(rawValue: appIconRaw), current.normalized != current {
                appIconRaw = current.normalized.rawValue
            }
        }
        .onChange(of: appearanceRaw) { value in
            persist(value, forKey: HidigSettingsKeys.appearance)
            AppAppearanceController.apply(AppearancePreference(rawValue: value) ?? .system)
        }
        .onChange(of: fontRaw) { persist($0, forKey: HidigSettingsKeys.font) }
        .onChange(of: textSizeRaw) { persist($0, forKey: HidigSettingsKeys.textSize) }
        .onChange(of: sidebarColorRaw) { persist($0, forKey: HidigSettingsKeys.sidebarColor) }
        .onChange(of: appIconRaw) { value in
            persist(value, forKey: HidigSettingsKeys.appIcon)
            AppIconController.apply(AppIconPreference(rawValue: value) ?? .green)
        }
        .onChange(of: showDockIcon) { persist($0, forKey: HidigSettingsKeys.showDockIcon) }
        .onChange(of: openWindowOnLaunch) { persist($0, forKey: HidigSettingsKeys.openWindowOnLaunch) }
        .sheet(isPresented: $showsBrowserHelp) {
            BrowserSetupGuideSheet(isPresented: $showsBrowserHelp)
                .environmentObject(store)
        }
    }

    private var calendarSection: some View {
SoftPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Календарь").font(.headline)
                        Picker("Первый день недели", selection: $plannerWeekday) { Text("Понедельник").tag(2); Text("Воскресенье").tag(1) }
                        Toggle("24-часовой формат", isOn: $planner24Hours)
                        Picker("Часовой пояс", selection: $plannerZone) {
                            Text("Системный").tag("")
                            ForEach(["Europe/Moscow", "Europe/London", "Europe/Berlin", "Asia/Dubai", "America/New_York"], id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Масштаб времени", selection: $calendarHourHeight) { Text("96 pt / час").tag(96.0); Text("120 pt / час").tag(120.0); if calendarHourHeight != 96 && calendarHourHeight != 120 { Text("Текущий: \(Int(calendarHourHeight)) pt / час").tag(calendarHourHeight) } }
                        Text("Уменьшение движения используется из системных настроек macOS.").font(.caption).foregroundStyle(.secondary)
                    }
                }
    }

    private var appearanceSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                appearanceControls.frame(minWidth: 460, maxWidth: 560)
                appearancePreview.frame(width: 320)
            }
            appearanceControls
        }
    }
    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 25) {
            VStack(alignment: .leading, spacing: 10) {
                settingLabel("Режим")
                HStack(spacing: 8) {
                    ForEach(AppearancePreference.allCases) { option in
                        ThemeChoiceCard(option: option, isSelected: appearanceRaw == option.rawValue) { appearanceRaw = option.rawValue }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                settingLabel("Цветовая схема")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach([SidebarColorPreference.paper, .ink, .mist, .moss]) { option in
                        PaletteChoiceCard(option: option, isSelected: sidebarColorRaw == option.rawValue) { sidebarColorRaw = option.rawValue }
                    }
                }
                DisclosureGroup("Другие палитры") {
                    LazyVGrid(columns: threeColumns, spacing: 8) {
                        ForEach(SidebarColorPreference.allCases.filter { ![.paper, .ink, .mist, .moss].contains($0) }) { option in
                            PaletteChoiceCard(option: option, isSelected: sidebarColorRaw == option.rawValue) { sidebarColorRaw = option.rawValue }
                        }
                    }.padding(.top, 8)
                }.hidigFont(size: 11).foregroundStyle(HidigPalette.secondary)
            }
            fontChoices
            VStack(alignment: .leading, spacing: 10) {
                settingLabel("Иконки разделов")
                HStack(spacing: 8) {
                    ForEach(HidigIconPack.allCases) { pack in
                        ChoicePill(title: pack.title, isSelected: iconPackRaw == pack.rawValue) { iconPackRaw = pack.rawValue }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                settingLabel("Иконка приложения")
                HStack(spacing: 12) {
                    ForEach([AppIconPreference.doors, .medallion]) { option in iconChoice(option) }
                }
                DisclosureGroup("Предыдущие иконки") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(AppIconPreference.allCases.filter { $0 != .doors && $0 != .medallion }) { option in iconChoice(option) }
                    }.padding(.top, 8)
                }.hidigFont(size: 11).foregroundStyle(HidigPalette.secondary)
            }
            Button("Вернуть оформление «Бумага»", action: resetAppearance).buttonStyle(GhostButtonStyle())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var fontChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Шрифт интерфейса")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach([HidigFontPreference.golos, .onest, .manrope, .inter]) { option in
                    Button { fontRaw = option.rawValue } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(option.title).font(option.font(size: 15, weight: .medium, design: nil))
                            Text("Планы становятся яснее").font(option.font(size: 11, weight: .regular, design: nil))
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(SelectionRowButtonStyle(isSelected: fontRaw == option.rawValue))
                }
            }
            DisclosureGroup("Системные шрифты") {
                Picker("Системный шрифт", selection: $fontRaw) {
                    ForEach(HidigFontPreference.allCases) { Text($0.title).tag($0.rawValue) }
                }.padding(.top, 8)
            }.hidigFont(size: 11).foregroundStyle(HidigPalette.secondary)
            HStack(spacing: 8) {
                Text("Размер текста").hidigFont(size: 11).foregroundStyle(HidigPalette.secondary)
                ForEach(HidigTextSizePreference.allCases) { option in
                    ChoicePill(title: option.title, isSelected: textSizeRaw == option.rawValue) { textSizeRaw = option.rawValue }
                }
            }
        }
    }
    private func iconChoice(_ option: AppIconPreference) -> some View {
        Button { appIconRaw = option.rawValue } label: {
            VStack(spacing: 5) {
                AppIconPreview(style: option, size: 64)
                Text(option.title).hidigFont(size: 11)
            }.padding(8)
        }.buttonStyle(SelectionRowButtonStyle(isSelected: appIconRaw == option.rawValue))
            .accessibilityLabel("Иконка " + option.title)
    }
    private var appearancePreview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Предпросмотр").hidigFont(size: 12).foregroundStyle(HidigPalette.secondary)
            SoftPanel {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Мой день").hidigFont(size: 16, weight: .semibold)
                    ForEach(Array(store.visibleManagedTasks.prefix(2))) { task in
                        HStack(alignment: .top, spacing: 9) {
                            HidigCheckmarkBox(isChecked: task.status == .completed, size: 16)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title).hidigFont(size: 14, weight: .medium).lineLimit(2)
                                Text(task.scheduleLabel)
                                    .hidigFont(size: 11).foregroundStyle(HidigPalette.secondary)
                            }
                        }
                        Divider().overlay(HidigPalette.line)
                    }
                    Text("Один шаг к важному").hidigFont(size: 13).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(HidigPalette.lettuce).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text("Кириллица, латиница, цифры").hidigFont(size: 11).foregroundStyle(HidigPalette.secondary)
            Text("Планы становятся яснее").hidigFont(size: 23, weight: .medium)
            Text("Aa Бб Дд Жж · 0123456789").hidigFont(size: 12).foregroundStyle(HidigPalette.secondary)
        }
    }

    private var applicationSection: some View {
        settingsSection("Запуск", description: "Поведение приложения после входа в macOS.") {
            HidigCheckboxRow(title: "Запускать вместе с macOS", isOn: launchAtLogin) {
                updateLaunchAtLogin(!launchAtLogin)
            }
            HidigCheckboxRow(title: "Открывать большое окно при запуске", isOn: openWindowOnLaunch) {
                openWindowOnLaunch.toggle()
            }
            HidigCheckboxRow(title: "Показывать значок в Dock", isOn: showDockIcon) {
                showDockIcon.toggle()
            }
            Text("Иконка в строке меню показывается всегда, чтобы приложение нельзя было потерять при скрытом Dock.")
                .hidigFont(size: 10)
                .foregroundStyle(HidigPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tickTickSection: some View {
        settingsSection("Импорт задач", description: "hidigFocus хранит задачи и работает самостоятельно. TickTick доступен как источник разового импорта.") {
            Button("Открыть импорт из TickTick") { store.selectedSection = .tickTick }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var browserSection: some View {
        settingsSection("Браузеры", description: "Приложения macOS блокируются напрямую. Для блокировки сайтов браузеру нужен отдельный модуль.") {
            browserStatus("Chrome, Edge, Brave, Яндекс", isActive: store.browserExtensionIsConnected)
            HStack(spacing: 7) {
                Button("Папка Chrome") { store.revealBrowserExtension() }.buttonStyle(SecondaryButtonStyle())
                Button("Путь") { store.copyBrowserExtensionPath() }.buttonStyle(GhostButtonStyle())
                Button {
                    showsBrowserHelp = true
                } label: {
                    Label("Как подключить", systemImage: "info.circle")
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private var journalSection: some View {
        settingsSection("Журнал", description: "Локальные Markdown-файлы с автоматическим сохранением.") {
            Text(journal.journalSaveState.title)
                .hidigFont(size: 11, weight: .medium)
                .foregroundStyle(journal.journalSaveState.isError ? HidigPalette.warning : HidigPalette.secondary)
            Button("Открыть папку журнала") { store.revealJournalFolder() }.buttonStyle(SecondaryButtonStyle())
        }
    }

    private func settingsSection<Content: View>(_ title: String, description: String, @ViewBuilder content: () -> Content) -> some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 11) {
                Text(title).hidigFont(size: 16, weight: .semibold)
                Text(description)
                    .hidigFont(size: 11)
                    .foregroundStyle(HidigPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingLabel(_ title: String) -> some View {
        Text(title)
            .hidigFont(size: 12, weight: .semibold)
            .foregroundStyle(HidigPalette.secondary)
    }

    private func browserStatus(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            StatusDot(isActive: isActive)
            Text(title).hidigFont(size: 11, weight: .semibold)
            Spacer()
            Text(isActive ? "подключено" : "нет сигнала")
                .hidigFont(size: 9, weight: .medium)
                .foregroundStyle(HidigPalette.secondary)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginController.isEnabled
        } catch {
            store.errorMessage = "Не удалось изменить автозапуск: \(error.localizedDescription)"
            launchAtLogin = LaunchAtLoginController.isEnabled
        }
    }

    private func resetAppearance() {
        fontRaw = HidigFontPreference.golos.rawValue
        sidebarColorRaw = SidebarColorPreference.paper.rawValue
        appIconRaw = AppIconPreference.doors.rawValue
        iconPackRaw = HidigIconPack.duotone.rawValue
    }

    private func persist(_ value: Any, forKey key: String) {
        HidigRuntime.defaults.set(value, forKey: key)
        HidigRuntime.defaults.synchronize()
    }
}

private struct ThemeChoiceCard: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let option: AppearancePreference
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: option.systemImage)
                Text(option.title).hidigFont(size: 12, weight: .medium)
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(HidigPalette.forest)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(isSelected ? HidigPalette.lettuce.opacity(0.3) : (isHovered ? HidigPalette.hover : HidigPalette.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(isSelected || isHovered ? HidigPalette.focusRing : HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Выбрано" : "Не выбрано")
        .onHover { isHovered = $0 }
    }
}

struct ChoicePill: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .hidigFont(size: 11, weight: .semibold)
                .padding(.horizontal, 11)
                .frame(minHeight: 34)
                .contentShape(Rectangle())
        }
            .buttonStyle(SelectionRowButtonStyle(isSelected: isSelected))
    }
}

private struct ColorSwatch: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(isSelected ? HidigPalette.forest : HidigPalette.line, lineWidth: isSelected ? 2 : 1))
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .hidigFont(size: 10, weight: .bold)
                            .foregroundStyle(SidebarColorResolver.foreground(preference: nil, customHex: color.hexString ?? "#FFFFFF"))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct PaletteChoiceCard: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let option: SidebarColorPreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    palettePreview(option.theme(isDark: false), systemImage: "sun.max.fill")
                    palettePreview(option.theme(isDark: true), systemImage: "moon.fill")
                }
                Text(option.title)
                    .hidigFont(size: 10, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(HidigPalette.forest)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(isSelected ? HidigPalette.focusRing : HidigPalette.line, lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Выбрано" : "Не выбрано")
    }

    private func palettePreview(_ theme: HidigThemeColors, systemImage: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Color(hex: theme.canvas)
            HStack(spacing: 0) {
                Color(hex: theme.sidebar).frame(width: 14)
                Color(hex: theme.surface)
                Color(hex: theme.accent).frame(width: 9)
            }
            Image(systemName: systemImage)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color(hex: theme.text))
                .padding(3)
        }
        .frame(height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.line)))
    }
}

private struct BrowserSetupGuideSheet: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @State private var copiedBrowser: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                PageTitle(
                    eyebrow: "Подключение",
                    title: "Браузеры",
                    subtitle: "Для блокировки сайтов браузеру нужен отдельный модуль. Одного приложения macOS для этого недостаточно."
                )
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(HidigIconButtonStyle())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    guideCard(
                        title: "Chrome, Edge, Brave, Opera и Яндекс Браузер",
                        steps: [
                            "Откройте страницу расширений и включите режим разработчика.",
                            "Нажмите «Загрузить распакованное расширение» и выберите папку BrowserExtension.",
                            "Закрепите расширение на панели. Статус в hidigFocus должен смениться на «подключено» в течение 30 секунд."
                        ],
                        addresses: [
                            ("Chrome", "chrome://extensions"),
                            ("Edge", "edge://extensions"),
                            ("Brave", "brave://extensions"),
                            ("Opera", "opera://extensions"),
                            ("Яндекс", "browser://extensions")
                        ]
                    )

                    guideCard(
                        title: "Firefox",
                        steps: [
                            "Текущая сборка расширения Firefox не поддерживает.",
                            "Для Firefox нужен отдельный пакет и отдельная проверка совместимости правил. Это не считается подключённым браузером в текущей версии."
                        ],
                        addresses: []
                    )
                }
            }

            HStack {
                Button("Показать папку расширения") { store.revealBrowserExtension() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Готово") { isPresented = false }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(26)
        .frame(width: 680, height: 650)
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.canvas)
    }

    private func guideCard(title: String, steps: [String], addresses: [(String, String)]) -> some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).hidigFont(size: 15, weight: .semibold)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .hidigFont(size: 10, weight: .bold, design: .rounded)
                            .foregroundStyle(HidigPalette.controlFill)
                            .frame(width: 22, height: 22)
                            .background(HidigPalette.lettuce.opacity(0.35))
                            .clipShape(Circle())
                        Text(step)
                            .hidigFont(size: 11)
                            .foregroundStyle(HidigPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !addresses.isEmpty {
                    Divider().overlay(HidigPalette.line)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            ForEach(addresses, id: \.0) { browser, address in
                                Button {
                                    store.copyBrowserExtensionsAddress(address)
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        copiedBrowser = browser
                                    }
                                } label: {
                                    Label(browser, systemImage: "doc.on.doc")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .help("Скопировать \(address)")
                            }
                        }
                        if let copiedBrowser {
                            Label(
                                "Адрес для \(copiedBrowser) скопирован. Вставьте его в адресную строку браузера.",
                                systemImage: "checkmark.circle.fill"
                            )
                            .hidigFont(size: 10, weight: .medium)
                            .foregroundStyle(HidigPalette.secondary)
                            .transition(.opacity)
                        }
                    }
                }
            }
        }
    }
}
