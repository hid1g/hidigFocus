import AppKit
import SwiftUI

@main
struct HidigFocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @AppStorage(HidigSettingsKeys.font) private var fontRaw = HidigFontPreference.system.rawValue
    @AppStorage(HidigSettingsKeys.textSize) private var textSizeRaw = HidigTextSizePreference.standard.rawValue
    @AppStorage(HidigSettingsKeys.appIcon) private var appIconRaw = AppIconPreference.green.rawValue
    @AppStorage(HidigSettingsKeys.sidebarColor) private var paletteRaw = SidebarColorPreference.sage.rawValue
    @AppStorage(HidigSettingsKeys.customSidebarColor) private var customPaletteHex = "#E5EFDA"
    @AppStorage(HidigSettingsKeys.showDockIcon) private var showDockIcon = true
    @AppStorage(HidigSettingsKeys.appearance) private var appearanceRaw = AppearancePreference.system.rawValue

    init() {
        UserDefaults.standard.register(defaults: [
            HidigSettingsKeys.font: HidigFontPreference.system.rawValue,
            HidigSettingsKeys.appearance: AppearancePreference.system.rawValue,
            HidigSettingsKeys.textSize: HidigTextSizePreference.standard.rawValue,
            HidigSettingsKeys.sidebarColor: SidebarColorPreference.sage.rawValue,
            HidigSettingsKeys.customSidebarColor: "#E5EFDA",
            HidigSettingsKeys.appIcon: AppIconPreference.green.rawValue,
            HidigSettingsKeys.showDockIcon: true,
            HidigSettingsKeys.openWindowOnLaunch: true
        ])
    }

    var body: some Scene {
        Window("hidigFocus", id: "main") {
            RootView()
                .id("\(paletteRaw)-\(customPaletteHex)")
                .environmentObject(store)
                .environment(\.hidigFontPreference, selectedFont)
                .environment(\.hidigTextScale, selectedTextSize.scale)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear { applyApplicationAppearance() }
                .onChange(of: appIconRaw) { _ in applyApplicationAppearance() }
                .onChange(of: showDockIcon) { _ in applyApplicationAppearance() }
                .onChange(of: appearanceRaw) { _ in applyApplicationAppearance() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("hidigFocus") {
                Button("Синхронизировать TickTick") {
                    Task { await store.refreshConnectionAndTasks() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .id("\(paletteRaw)-\(customPaletteHex)")
                .environmentObject(store)
                .environment(\.hidigFontPreference, selectedFont)
                .environment(\.hidigTextScale, selectedTextSize.scale)
        } label: {
            Image(systemName: "leaf.fill")
                .accessibilityLabel("hidigFocus")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .id("\(paletteRaw)-\(customPaletteHex)")
                .environmentObject(store)
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

        let defaults = UserDefaults.standard
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
        UserDefaults.standard.synchronize()
    }

    @objc private func windowDidClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.applySavedAppearance()
        }
    }

    @MainActor
    private func applySavedAppearance() {
        let defaults = UserDefaults.standard
        let icon = AppIconPreference(rawValue: defaults.string(forKey: HidigSettingsKeys.appIcon) ?? "") ?? .green
        let appearance = AppearancePreference(rawValue: defaults.string(forKey: HidigSettingsKeys.appearance) ?? "") ?? .system
        AppAppearanceController.apply(appearance)
        ApplicationDockController.apply(
            showDockIcon: defaults.bool(forKey: HidigSettingsKeys.showDockIcon),
            icon: icon
        )
    }
}
