import Foundation

/// Resolve the packaged macOS resources before SwiftPM's development fallback.
/// The generated accessor in newer SwiftPM versions checks the app root rather
/// than Contents/Resources; using it first can reach a protected source folder.
enum HidigResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("hidigFocus_hidigFocus.bundle"),
           let packaged = Bundle(url: url) {
            return packaged
        }
        return Bundle.module
    }()
}
