import XCTest
@testable import hidigFocus

final class CalendarCardLayoutTests: XCTestCase {
    func testPackagedInterfaceResourcesRemainAvailable() {
        XCTAssertNotNil(HidigResources.bundle.url(forResource: "hidigFocus-icon-master", withExtension: "png"))
        let manifest = HidigResources.bundle.resourceURL?.appendingPathComponent("BrowserExtension/manifest.json")
        XCTAssertTrue(manifest.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
    }

    func testFortyFiveMinuteCardReservesTimeBeforeTitleWrapping() {
        let card = CalendarCardLayout(height: 72, width: 210, scale: 1, font: .system)
        XCTAssertTrue(card.showsTime)
        XCTAssertGreaterThanOrEqual(card.titleLines, 2)
        XCTAssertLessThanOrEqual(card.requiredHeight, card.contentHeight)
    }

    func testAllFontsAndTextSizesFitCalendarZoomAndNarrowLanes() {
        for font in HidigFontPreference.allCases {
            for scale in HidigTextSizePreference.allCases.map(\.scale) {
                for height: CGFloat in [18, 24, 36, 48, 54, 72, 96, 144] {
                    for width: CGFloat in [48, 80, 110, 180, 300] {
                        let card = CalendarCardLayout(height: height, width: width, scale: scale, font: font, hasPriority: true)
                        if card.contentHeight >= card.titleLineHeight {
                            XCTAssertLessThanOrEqual(card.requiredHeight, card.contentHeight, "\(font) \(scale) \(height) \(width)")
                        } else {
                            XCTAssertFalse(card.showsTime)
                            XCTAssertEqual(card.titleLines, 1)
                        }
                    }
                }
            }
        }
    }

    func testEveryPaletteHasReadablePrimaryButtonTextInBothAppearances() {
        for palette in SidebarColorPreference.allCases {
            for dark in [false, true] {
                let colors = palette.theme(isDark: dark)
                XCTAssertGreaterThanOrEqual(colors.contrastRatio(with: colors.onAccent), 4.5, "\(palette) dark=\(dark)")
            }
        }
    }
}
