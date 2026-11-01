import SwiftUI

struct TickTickView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var integration: IntegrationState
    @EnvironmentObject private var store: AppStore
    @State private var copied = false
    @State private var googleClientID = HidigRuntime.defaults.string(forKey: "googleOAuthClientID") ?? ""
    @State private var googleClientSecret = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageTitle(
                    eyebrow: "",
                    title: "Интеграции",
                    subtitle: "hidigFocus работает самостоятельно. Внешние сервисы подключаются по желанию."
                )

                SoftPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Импорт TickTick")
                            .hidigFont(size: 20, weight: .bold)
                        Text("Импорт запускается вручную и добавляет отсутствующие задачи. Существующие задачи и ваши правки сохраняются. Перед импортом создаётся резервная копия.")
                            .hidigFont(size: 12)
                            .foregroundStyle(HidigPalette.secondary)
                        Text("Подключение нужно только для импорта. Фоновая синхронизация отключена.")
                            .hidigFont(size: 12).foregroundStyle(HidigPalette.secondary)
                        connectionExplanation.hidigFont(size: 12).foregroundStyle(HidigPalette.secondary)
                        connectionActions
                        if integration.isSynchronizing || integration.isImportingTickTick { ProgressView() }
                        if let error = integration.tickTickImportError {
                            Text(error).hidigFont(size: 12).foregroundStyle(HidigPalette.warning)
                        }
                        if let preview = integration.tickTickImportPreview {
                            Text("Найдено: списков — \(preview.lists), активных задач — \(preview.activeTasks), выполненных — \(preview.completedTasks), папок с доступными названиями — \(preview.folders).")
                                .hidigFont(size: 13, weight: .semibold)
                            HStack {
                                Button("Добавить задачи в hidigFocus") { store.performPreparedTickTickImport() }
                                    .buttonStyle(PrimaryButtonStyle())
                                Button("Обновить подсчёт") { Task { await store.prepareTickTickImport() } }
                                    .buttonStyle(SecondaryButtonStyle())
                            }.disabled(integration.isSynchronizing || integration.isImportingTickTick)
                        } else if integration.connectionState == .connected {
                            Button("Проверить доступные данные") { Task { await store.prepareTickTickImport() } }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(integration.isSynchronizing || integration.isImportingTickTick)
                        }
                        if let report = store.state.taskImportHistory.first {
                            Text("Последний импорт: добавлено — \(report.imported), обновлено — \(report.updated), без изменений — \(report.skipped), ошибок — \(report.failed).")
                                .hidigFont(size: 11)
                                .foregroundStyle(HidigPalette.secondary)
                        }
                        Text("Импорт сохраняет доступные названия списков. Папки без названия не добавляются.")
                            .hidigFont(size: 11)
                            .foregroundStyle(HidigPalette.warning)
                    }
                }

                SoftPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            StatusDot(isActive: store.state.googleCalendarConnection.isConnected)
                            Text("Google Calendar")
                                .hidigFont(size: 20, weight: .bold)
                            Spacer()
                            if integration.isGoogleSynchronizing { ProgressView() }
                        }
                        if store.state.googleCalendarConnection.isConnected {
                            Text(googleLastSyncText)
                                .hidigFont(size: 12)
                                .foregroundStyle(HidigPalette.secondary)
                            ForEach(integration.googleCalendars) { calendar in
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
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 50)
            .frame(maxWidth: 960, alignment: .leading)
        }
    }

    @ViewBuilder
    private var connectionExplanation: some View {
        switch integration.connectionState {
        case .notRequested:
            Text("Доступ к TickTick ещё не проверялся. Задачи, календарь и блокировки работают на локальных данных.")
        case .checking:
            Text("Проверяем наличие утилиты и авторизацию.")
        case .cliMissing:
            Text("На этом Mac TickTick CLI пока не установлен. Скопируйте команду, выполните её в Терминале и вернитесь сюда.")
        case .signedOut:
            Text("Утилита установлена, но аккаунт не авторизован.")
        case .connecting:
            Text("Завершите вход в открывшемся окне браузера.")
        case .connected:
            Text("Доступ для импорта подтверждён. Выберите данные и запустите импорт.")
        case .failed(let message):
            Text(message)
        }
    }

    @ViewBuilder
    private var connectionActions: some View {
        switch integration.connectionState {
        case .notRequested:
            SyncButton()
        case .cliMissing:
            Text("Для импорта установите TickTick CLI: npm install -g @ticktick/ticktick-cli")
                .hidigFont(size: 12).foregroundStyle(HidigPalette.secondary)
            HStack {
                Button(copied ? "Скопировано" : "Копировать команду") {
                    store.copyCLIInstallCommand(); copied = true
                }
                SyncButton()
            }.buttonStyle(SecondaryButtonStyle())
        case .signedOut, .failed:
            HStack {
                Button("Войти для импорта") { Task { await store.connectTickTick() } }
                    .buttonStyle(PrimaryButtonStyle())
                SyncButton()
            }.disabled(integration.isSynchronizing || integration.isImportingTickTick)
        case .connected:
            Button("Отключить доступ к импорту") { Task { await store.disconnectTickTick() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(integration.isSynchronizing || integration.isImportingTickTick)
        default:
            EmptyView()
        }
    }

    private var googleLastSyncText: String {
        if let date = store.state.googleCalendarConnection.lastSuccessfulSync {
            return "Последняя успешная синхронизация: \(date.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Аккаунт подключён. Выберите календари и запустите синхронизацию."
    }
}
