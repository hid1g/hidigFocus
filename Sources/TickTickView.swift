import SwiftUI

struct TickTickView: View {
    @EnvironmentObject private var store: AppStore
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageTitle(
                    eyebrow: "Подключения",
                    title: "Интеграции",
                    subtitle: "Внешние источники дополняют локальные задачи hidigFocus. Сейчас доступен TickTick."
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
}
