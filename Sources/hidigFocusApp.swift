import AppKit
import SwiftUI

@main
struct HidigFocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var storeOwner = AppStoreOwner()
    private var store: AppStore { storeOwner.store }
    @AppStorage(HidigSettingsKeys.font, store: HidigRuntime.defaults) private var fontRaw = HidigFontPreference.system.rawValue
    @AppStorage(HidigSettingsKeys.textSize, store: HidigRuntime.defaults) private var textSizeRaw = HidigTextSizePreference.standard.rawValue
    @AppStorage(HidigSettingsKeys.appIcon, store: HidigRuntime.defaults) private var appIconRaw = AppIconPreference.green.rawValue
    @AppStorage(HidigSettingsKeys.sidebarColor, store: HidigRuntime.defaults) private var paletteRaw = SidebarColorPreference.ocean.rawValue
    @AppStorage(HidigSettingsKeys.customSidebarColor, store: HidigRuntime.defaults) private var customPaletteHex = "#E5EFDA"
    @AppStorage(HidigSettingsKeys.showDockIcon, store: HidigRuntime.defaults) private var showDockIcon = true
    @AppStorage(HidigSettingsKeys.appearance, store: HidigRuntime.defaults) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage("qa.reduceMotion", store: HidigRuntime.defaults) private var qaReduceMotion = false

    init() {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--export-icon",
           let style = AppIconPreference(rawValue: CommandLine.arguments[2]) {
            do {
                try AppIconController.exportIconSet(style, to: URL(fileURLWithPath: CommandLine.arguments[3]))
                exit(0)
            } catch {
                fputs("Icon export failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        _ = HidigFontRegistry.registration
        PrintDesign.applyFirstLaunch(defaults: HidigRuntime.defaults)
        HidigRuntime.defaults.register(defaults: [
            HidigSettingsKeys.font: HidigFontPreference.system.rawValue,
            HidigSettingsKeys.appearance: AppearancePreference.system.rawValue,
            HidigSettingsKeys.textSize: HidigTextSizePreference.standard.rawValue,
            HidigSettingsKeys.sidebarColor: SidebarColorPreference.ocean.rawValue,
            HidigSettingsKeys.customSidebarColor: "#E5EFDA",
            HidigSettingsKeys.appIcon: AppIconPreference.green.rawValue,
            HidigSettingsKeys.showDockIcon: true,
            HidigSettingsKeys.openWindowOnLaunch: true
        ])
    }

    var body: some Scene {
        Window("hidigFocus", id: "main") {
            RootView()
                .modifier(HidigQAMotionModifier())
                .environment(\.hidigPaletteIdentity, "\(paletteRaw)-\(customPaletteHex)")
                .environmentObject(store)
                .environmentObject(store.journal)
                .environmentObject(store.saving)
                .environmentObject(store.integration)
                .environmentObject(store.focusPresentation)
                .environmentObject(store.planner)
                .environmentObject(store.reminderService)
                .environment(\.hidigFontPreference, selectedFont)
                .environment(\.hidigTextScale, selectedTextSize.scale)
                .frame(minWidth: 760, minHeight: 680)
                .onAppear { applyApplicationAppearance() }
                .onChange(of: appIconRaw) { _ in applyApplicationAppearance() }
                .onChange(of: showDockIcon) { _ in applyApplicationAppearance() }
                .onChange(of: appearanceRaw) { _ in applyApplicationAppearance() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новая задача") { store.selectedSection = .tasks; _ = store.addManagedTask(named: "Новая задача") }.keyboardShortcut("n", modifiers: [.command]).disabled(store.dataIsReadOnly)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Отменить действие с задачей") { store.undoTaskAction() }.keyboardShortcut("z", modifiers: [.command]).disabled(store.dataIsReadOnly)
                Button("Повторить действие с задачей") { store.redoTaskAction() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store.dataIsReadOnly)
            }
            if HidigRuntime.isIsolated {
                CommandMenu("Проверка") {
                    Button("Сохранить снимок") { HidigQAEvidence.captureWindow() }.keyboardShortcut("s", modifiers: [.command, .option, .shift])
                    Button("Окно 1440 × 960") { HidigQAEvidence.resizeWindow(width: 1440, height: 960) }
                    Button("Окно 1280 × 800") { HidigQAEvidence.resizeWindow(width: 1280, height: 800) }
                    Button("Окно 1024 × 768") { HidigQAEvidence.resizeWindow(width: 1024, height: 768) }
                    Button("Окно 760 × 960") { HidigQAEvidence.resizeWindow(width: 760, height: 960) }
                    Divider()
                    Toggle("Уменьшение движения — проверка", isOn: $qaReduceMotion)
                }
            }
            CommandMenu("hidigFocus") {
                Button("Импорт из TickTick…") {
                    store.selectedSection = .tickTick
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Window("Помодоро", id: "focus") {
            FocusView(compact: true)
                .modifier(HidigQAMotionModifier())
                .environment(\.hidigPaletteIdentity, "\(paletteRaw)-\(customPaletteHex)")
                .environmentObject(store)
                .environmentObject(store.journal)
                .environmentObject(store.saving)
                .environmentObject(store.integration)
                .environmentObject(store.focusPresentation)
                .environment(\.hidigFontPreference, selectedFont)
                .environment(\.hidigTextScale, selectedTextSize.scale)
                .frame(minWidth: 360, minHeight: 440)
        }
        .defaultSize(width: 420, height: 540)

        Window("Быстрые задачи", id: "quick") {
            MenuBarPanel()
                .modifier(HidigQAMotionModifier())
                .environment(\.hidigPaletteIdentity, "\(paletteRaw)-\(customPaletteHex)")
                .environmentObject(store)
                .environmentObject(store.journal)
                .environmentObject(store.saving)
                .environmentObject(store.integration)
                .environmentObject(store.focusPresentation)
                .environmentObject(store.planner)
                .environmentObject(store.reminderService)
                .environment(\.hidigFontPreference, selectedFont)
                .environment(\.hidigTextScale, selectedTextSize.scale)
        }.windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarPanel()
                .modifier(HidigQAMotionModifier())
                .environment(\.hidigPaletteIdentity, "\(paletteRaw)-\(customPaletteHex)")
                .environmentObject(store)
                .environmentObject(store.journal)
                .environmentObject(store.saving)
                .environmentObject(store.integration)
                .environmentObject(store.focusPresentation)
                .environmentObject(store.planner)
                .environmentObject(store.reminderService)
                .environment(\.hidigFontPreference, selectedFont)
                .environment(\.hidigTextScale, selectedTextSize.scale)
        } label: {
            Image(systemName: "scope")
                .accessibilityLabel("hidigFocus")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modifier(HidigQAMotionModifier())
                .environment(\.hidigPaletteIdentity, "\(paletteRaw)-\(customPaletteHex)")
                .environmentObject(store)
                .environmentObject(store.journal)
                .environmentObject(store.saving)
                .environmentObject(store.integration)
                .environmentObject(store.focusPresentation)
                .environmentObject(store.planner)
                .environmentObject(store.reminderService)
                .environment(\.hidigFontPreference, selectedFont)
                .environment(\.hidigTextScale, selectedTextSize.scale)
                .frame(width: 760, height: 720)
                .background(HidigPalette.canvas)
        }
    }

    private var selectedFont: HidigFontPreference {
        HidigFontPreference(rawValue: fontRaw) ?? .system
    }

    private var selectedTextSize: HidigTextSizePreference {
        HidigTextSizePreference(rawValue: textSizeRaw) ?? .standard
    }

    @MainActor
    private func applyApplicationAppearance() {
        AppAppearanceController.apply(AppearancePreference(rawValue: appearanceRaw) ?? .system)
        ApplicationDockController.apply(
            showDockIcon: showDockIcon,
            icon: AppIconPreference(rawValue: appIconRaw) ?? .green
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let error = HidigTerminationGate.prepare?() {
            let alert = NSAlert(); alert.messageText = "Не удалось сохранить изменения"
            alert.informativeText = error + "\nПриложение остаётся открытым. Повторите сохранение после устранения ошибки."
            alert.addButton(withTitle: "Вернуться в приложение"); alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applySavedAppearance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        let defaults = HidigRuntime.defaults
        guard !defaults.bool(forKey: HidigSettingsKeys.openWindowOnLaunch) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApplication.shared.windows
                .filter { $0.title == "hidigFocus" }
                .forEach { $0.close() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applySavedAppearance()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HidigRuntime.defaults.synchronize()
    }

    @objc private func windowDidClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.applySavedAppearance()
        }
    }

    @MainActor
    private func applySavedAppearance() {
        let defaults = HidigRuntime.defaults
        let icon = AppIconPreference(rawValue: defaults.string(forKey: HidigSettingsKeys.appIcon) ?? "") ?? .green
        let appearance = AppearancePreference(rawValue: defaults.string(forKey: HidigSettingsKeys.appearance) ?? "") ?? .system
        AppAppearanceController.apply(appearance)
        ApplicationDockController.apply(
            showDockIcon: defaults.bool(forKey: HidigSettingsKeys.showDockIcon),
            icon: icon
        )
    }
}

/// Keep one store alive without subscribing the entire Scene tree to task/UI updates.
/// Individual screens retain their own EnvironmentObject subscriptions.
@MainActor
private final class AppStoreOwner: ObservableObject {
    let store: AppStore
    init() {
        store = AppStore()
        store.startIsolatedFocusClock()
        HidigTerminationGate.prepare = { [weak store] in store?.prepareForTermination() }
    }
}
