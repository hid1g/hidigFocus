import SwiftUI

struct TickTickView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @State private var copied = false
    @State private var googleClientID = UserDefaults.standard.string(forKey: "googleOAuthClientID") ?? ""
    @State private var googleClientSecret = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageTitle(
                    eyebrow: "Подключения",
                    title: "Интеграции",
                    subtitle: "Внешние календари и источники дополняют локальные задачи hidigFocus."
                )

                SoftPanel {
                    HStack(alignment: .top, spacing: 18) {
                        StatusDot(isActive: store.connectionState == .connected)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TickTick")
                                .hidigFont(size: 20, weight: .bold, design: .rounded)
                            Text(store.connectionState.title)
                                .hidigFont(size: 18, weight: .semibold)
                            connectionExplanation
                                .hidigFont(size: 12)
                                .foregroundStyle(HidigPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            connectionActions
                                .padding(.top, 5)
                        }
                        Spacer()
                        if store.isSynchronizing { ProgressView() }
                    }
                }

                SoftPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Перенос данных")
                        Text("Импорт TickTick")
                            .hidigFont(size: 20, weight: .bold, design: .rounded)
                        Text("Сначала выполняется предварительный подсчёт. Перед записью создаётся резервная копия локального состояния; повторный импорт пропускает задачи с тем же исходным ID.")
                            .hidigFont(size: 12)
                            .foregroundStyle(HidigPalette.secondary)
                        if let preview = store.tickTickImportPreview {
                            Text("Найдено: списков — \(preview.lists), активных задач — \(preview.activeTasks), выполненных — \(preview.completedTasks), папок с доступными названиями — \(preview.folders).")
                                .hidigFont(size: 13, weight: .semibold)
                            HStack {
                                Button("Импортировать") { store.performPreparedTickTickImport() }
                                    .buttonStyle(PrimaryButtonStyle())
                                Button("Обновить подсчёт") { Task { await store.prepareTickTickImport() } }
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                        } else {
                            Button("Проверить доступные данные") { Task { await store.prepareTickTickImport() } }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(store.connectionState != .connected || store.isImportingTickTick)
                        }
                        if let report = store.state.taskImportHistory.first {
                            Text("Последний импорт: перенесено — \(report.imported), пропущено — \(report.skipped), ошибок — \(report.failed).")
                                .hidigFont(size: 11)
                                .foregroundStyle(HidigPalette.secondary)
                        }
                        Text("Текущий CLI возвращает ID папки у списка, но не название папки. Поэтому папки не создаются с выдуманными названиями; для точной иерархии нужна резервная выгрузка TickTick.")
                            .hidigFont(size: 11)
                            .foregroundStyle(HidigPalette.warning)
                    }
                }

                SoftPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            StatusDot(isActive: store.state.googleCalendarConnection.isConnected)
                            Text("Google Calendar")
                                .hidigFont(size: 20, weight: .bold, design: .rounded)
                            Spacer()
                            if store.isGoogleSynchronizing { ProgressView() }
                        }
                        if store.state.googleCalendarConnection.isConnected {
                            Text(googleLastSyncText)
                                .hidigFont(size: 12)
                                .foregroundStyle(HidigPalette.secondary)
                            ForEach(store.googleCalendars) { calendar in
                                Toggle(isOn: Binding(
                                    get: { store.state.googleCalendarConnection.selectedCalendarIDs.contains(calendar.id) },
                                    set: { store.setGoogleCalendarSelected(calendar.id, selected: $0) }
                                )) {
                                    Text(calendar.summary)
                                }
                            }
                            HStack {
                                Button("Синхронизировать") { Task { await store.refreshGoogleCalendars() } }
                                    .buttonStyle(PrimaryButtonStyle())
                                Button("Отключить") { store.disconnectGoogleCalendar() }
                                    .buttonStyle(DestructiveButtonStyle())
                            }
                        } else {
                            Text("OAuth выполняется через Google. Токены и Client Secret сохраняются только в Keychain.")
                                .hidigFont(size: 12)
                                .foregroundStyle(HidigPalette.secondary)
                            TextField("Google OAuth Client ID", text: $googleClientID)
                                .textFieldStyle(HidigTextFieldStyle())
                            SecureField("Client Secret, если выдан для desktop-клиента", text: $googleClientSecret)
                                .textFieldStyle(HidigTextFieldStyle())
                            Button("Подключить Google Calendar") {
                                Task { await store.connectGoogleCalendar(clientID: googleClientID, clientSecret: googleClientSecret.isEmpty ? nil : googleClientSecret) }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let error = store.state.googleCalendarConnection.lastSyncError {
                            Text(error).hidigFont(size: 11).foregroundStyle(HidigPalette.warning)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionEyebrow(text: "Как работает проверка")
                    numberedStep("01", "Официальная консольная утилита TickTick получает задачи с датой выполнения сегодня.")
                    numberedStep("02", "hidigFocus автоматически проверяет задачи каждую минуту. Кнопка с круговыми стрелками запускает такую же проверку сразу.")
                    numberedStep("03", "Группа открывается только когда все назначенные ей задачи отмечены выполненными.")
                    numberedStep("04", "Пустой список или ошибка синхронизации не открывают доступ.")
                }

                SoftPanel {
                    VStack(alignment: .leading, spacing: 13) {
                        SectionEyebrow(text: "Блокировка сайтов")
                        HStack {
                            Text(store.browserExtensionURL == nil ? "Файлы расширения не найдены" : store.browserExtensionStatusText)
                                .hidigFont(size: 14, weight: .semibold)
                            Spacer()
                            StatusDot(isActive: store.browserExtensionIsConnected)
                        }
                        Text("Для Chrome, Edge и Brave нужно один раз загрузить локальное расширение hidigFocus. Оно получает правила только от приложения на этом Mac.")
                            .hidigFont(size: 12)
                            .foregroundStyle(HidigPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("1. Скопируйте адрес страницы расширений и вставьте его в браузер.\n2. Включите режим разработчика.\n3. Нажмите «Загрузить распакованное».\n4. Выберите папку, которую откроет кнопка ниже.")
                            .hidigFont(size: 12)
                            .lineSpacing(5)
                        HStack(spacing: 8) {
                            Button("Chrome") { store.copyBrowserExtensionsAddress("chrome://extensions") }
                            Button("Edge") { store.copyBrowserExtensionsAddress("edge://extensions") }
                            Button("Brave") { store.copyBrowserExtensionsAddress("brave://extensions") }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        HStack(spacing: 8) {
                            Button("Показать папку расширения") { store.revealBrowserExtension() }
                                .buttonStyle(PrimaryButtonStyle())
                            Button("Скопировать путь") { store.copyBrowserExtensionPath() }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        Text("После установки не удаляйте hidigFocus: расширение синхронизирует правила с локальным приложением каждые 30 секунд.")
                            .hidigFont(size: 11)
                            .foregroundStyle(HidigPalette.secondary)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 50)
            .frame(maxWidth: 960, alignment: .leading)
        }
    }

    @ViewBuilder
    private var connectionExplanation: some View {
        switch store.connectionState {
        case .checking:
            Text("Проверяем наличие утилиты и авторизацию.")
        case .cliMissing:
            Text("На этом Mac TickTick CLI пока не установлен. Скопируйте команду, выполните её в Терминале и вернитесь сюда.")
        case .signedOut:
            Text("Утилита установлена, но аккаунт не авторизован.")
        case .connecting:
            Text("Завершите вход в открывшемся окне браузера.")
        case .connected:
            Text(lastSyncText)
        case .failed(let message):
            Text(message)
        }
    }

    @ViewBuilder
    private var connectionActions: some View {
        switch store.connectionState {
        case .cliMissing:
            HStack {
                Text("npm install -g @ticktick/ticktick-cli")
                    .hidigFont(size: 11, design: .monospaced)
                    .padding(9)
                    .background(HidigPalette.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button(copied ? "Скопировано" : "Копировать") {
                    store.copyCLIInstallCommand()
                    copied = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        case .signedOut:
            Button("Войти в TickTick") { Task { await store.connectTickTick() } }
                .buttonStyle(PrimaryButtonStyle())
        case .connected, .failed:
            SyncButton()
        default:
            EmptyView()
        }
    }

    private func numberedStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 15) {
            Text(number)
                .hidigFont(size: 12, weight: .bold, design: .rounded)
                .foregroundStyle(HidigPalette.lettuceStrong)
                .frame(width: 25)
            Text(text)
                .hidigFont(size: 13)
                .foregroundStyle(HidigPalette.forestMuted)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var lastSyncText: String {
        if let date = store.state.lastSuccessfulSync {
            return "Последняя успешная синхронизация: \(date.formatted(date: .abbreviated, time: .shortened)). Получено задач: \(store.todayTasks.count)."
        }
        return "Аккаунт подключён. Запустите первую синхронизацию."
    }

    private var googleLastSyncText: String {
        if let date = store.state.googleCalendarConnection.lastSuccessfulSync {
            return "Последняя успешная синхронизация: \(date.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Аккаунт подключён. Выберите календари и запустите синхронизацию."
    }
}
