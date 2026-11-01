import Foundation

/// The approved catalog is decoded once. Rendering never performs file reads or parsing.
enum PrintTokens {
    struct Catalog: Decodable {
        let color: [String: [String: String]]
        let radius: [String: Double]
        let size: [String: Double]
        let motion: Motion
        struct Motion: Decodable {
            let hoverMs: Double
            let stateMs: Double
            let panelMs: Double
        }
    }
    static let catalog: Catalog? = {
        guard let url = HidigResources.bundle.url(forResource: "PrintTokens", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }()
    static func color(_ role: String, dark: Bool, fallback: String) -> String {
        catalog?.color[dark ? "dark" : "light"]?[role] ?? fallback
    }
    static let controlRadius = CGFloat(catalog?.radius["control"] ?? 5)
    static let panelRadius = CGFloat(catalog?.radius["panel"] ?? 7)
    static let popoverRadius = CGFloat(catalog?.radius["popover"] ?? 11)
    static let buttonHeight = CGFloat(catalog?.size["buttonMedium"] ?? 32)
    static let inputHeight = CGFloat(catalog?.size["input"] ?? 38)
    static let compactNavigationWidth = CGFloat(catalog?.size["sidebarCompact"] ?? 58)
    static let calendarHourHeight = catalog?.size["calendarHourDefault"] ?? 96
    static let hover = (catalog?.motion.hoverMs ?? 120) / 1000
    static let state = (catalog?.motion.stateMs ?? 180) / 1000
    static let panel = (catalog?.motion.panelMs ?? 240) / 1000
}
