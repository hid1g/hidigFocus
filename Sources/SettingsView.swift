import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @AppStorage(HidigSettingsKeys.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(HidigSettingsKeys.font) private var fontRaw = HidigFontPreference.system.rawValue
    @AppStorage(HidigSettingsKeys.textSize) private var textSizeRaw = HidigTextSizePreference.standard.rawValue
    @AppStorage(HidigSettingsKeys.sidebarColor) private var sidebarColorRaw = SidebarColorPreference.sage.rawValue
    @AppStorage(HidigSettingsKeys.customSidebarColor) private var customSidebarColorHex = "#E5EFDA"
    @AppStorage(HidigSettingsKeys.appIcon) private var appIconRaw = AppIconPreference.green.rawValue
    @AppStorage(HidigSettingsKeys.showDockIcon) private var showDockIcon = true
    @AppStorage(HidigSettingsKeys.openWindowOnLaunch) private var openWindowOnLaunch = true

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled
    @State private var showsBrowserHelp = false

    private let threeColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageTitle(
                    eyebrow: "Управление приложением",
                    title: "Настройки",
                    subtitle: "Оформление, запуск, интеграции и расположение локальных данных."
                )

                appearanceSection

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                    applicationSection
                    tickTickSection
                    browserSection
                    journalSection
                }

            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .frame(maxWidth: 820, alignment: .leading)
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

    private var appearanceSection: some View {
        settingsSection("Оформление", description: "Каждая палитра работает в светлом, тёмном и системном режиме. Настройка применяется ко всему интерфейсу.") {
            settingLabel("Тема")
            HStack(spacing: 10) {
                ForEach(AppearancePreference.allCases) { option in
                    ThemeChoiceCard(option: option, isSelected: appearanceRaw == option.rawValue) {
                        appearanceRaw = option.rawValue
                    }
                }
            }

            Divider().overlay(HidigPalette.line).padding(.vertical, 3)
            settingLabel("Шрифт")
            LazyVGrid(columns: threeColumns, spacing: 9) {
                ForEach(HidigFontPreference.allCases) { option in
                    Button { fontRaw = option.rawValue } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aa Бб").font(option.font(size: 18, weight: .semibold, design: nil))
                            Text(option.title).font(option.font(size: 11, weight: .medium, design: nil))
                        }
                        .foregroundStyle(HidigPalette.forest)
                        .padding(11)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SelectionRowButtonStyle(isSelected: fontRaw == option.rawValue))
                }
            }

            HStack(alignment: .center, spacing: 12) {
                settingLabel("Размер текста").frame(width: 110, alignment: .leading)
                ForEach(HidigTextSizePreference.allCases) { option in
                    ChoicePill(title: option.title, isSelected: textSizeRaw == option.rawValue) {
                        textSizeRaw = option.rawValue
                    }
                }
            }

            Divider().overlay(HidigPalette.line).padding(.vertical, 3)
            settingLabel("Палитра")
            LazyVGrid(columns: threeColumns, spacing: 9) {
                ForEach(SidebarColorPreference.allCases) { option in
                    PaletteChoiceCard(option: option, isSelected: sidebarColorRaw == option.rawValue) {
                        sidebarColorRaw = option.rawValue
                    }
                }
            }

            Divider().overlay(HidigPalette.line).padding(.vertical, 3)
            settingLabel("Иконка в Dock")
            HStack(spacing: 12) {
                ForEach(AppIconPreference.allCases) { option in
                    Button { appIconRaw = option.rawValue } label: {
                        VStack(spacing: 7) {
                            AppIconPreview(style: option, size: 48)
                            Text(option.title).hidigFont(size: 10, weight: .semibold)
                        }
                        .foregroundStyle(HidigPalette.forest)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SelectionRowButtonStyle(isSelected: appIconRaw == option.rawValue))
                }
            }

            Button("Вернуть стандартное оформление", action: resetAppearance)
                .buttonStyle(GhostButtonStyle())
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
        settingsSection("Интеграции", description: "TickTick: \(store.connectionState.title)") {
            HStack(spacing: 8) {
                StatusDot(isActive: store.connectionState == .connected)
                Text(lastSyncText).hidigFont(size: 11, weight: .medium)
            }
            SyncButton()
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
            Text(store.journalSaveState.title)
                .hidigFont(size: 11, weight: .medium)
                .foregroundStyle(store.journalSaveState.isError ? HidigPalette.warning : HidigPalette.secondary)
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
        Text(title.uppercased())
            .hidigFont(size: 10, weight: .bold, design: .rounded)
            .tracking(0.8)
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

    private var lastSyncText: String {
        guard let date = store.state.lastSuccessfulSync else { return "Ещё не синхронизировано" }
        return "Обновлено \(date.formatted(date: .omitted, time: .shortened))"
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
        appearanceRaw = AppearancePreference.system.rawValue
        fontRaw = HidigFontPreference.system.rawValue
        textSizeRaw = HidigTextSizePreference.standard.rawValue
        sidebarColorRaw = SidebarColorPreference.sage.rawValue
        customSidebarColorHex = "#E5EFDA"
        appIconRaw = AppIconPreference.green.rawValue

        let defaults = UserDefaults.standard
        defaults.set(AppearancePreference.system.rawValue, forKey: HidigSettingsKeys.appearance)
        defaults.set(HidigFontPreference.system.rawValue, forKey: HidigSettingsKeys.font)
        defaults.set(HidigTextSizePreference.standard.rawValue, forKey: HidigSettingsKeys.textSize)
        defaults.set(SidebarColorPreference.sage.rawValue, forKey: HidigSettingsKeys.sidebarColor)
        defaults.set("#E5EFDA", forKey: HidigSettingsKeys.customSidebarColor)
        defaults.set(AppIconPreference.green.rawValue, forKey: HidigSettingsKeys.appIcon)

        AppAppearanceController.apply(.system)
        AppIconController.apply(.green)
    }

    private func persist(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.synchronize()
    }
}

private struct ThemeChoiceCard: View {
    let option: AppearancePreference
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: option.systemImage)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? HidigPalette.lettuceStrong : HidigPalette.secondary)
                }
                Text(option.title).hidigFont(size: 12, weight: .semibold)
            }
            .foregroundStyle(HidigPalette.forest)
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(isSelected ? HidigPalette.lettuce.opacity(0.3) : (isHovered ? HidigPalette.hover : HidigPalette.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(isSelected || isHovered ? HidigPalette.focusRing : HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct ChoicePill: View {
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
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? HidigPalette.focusRing : HidigPalette.line, lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
