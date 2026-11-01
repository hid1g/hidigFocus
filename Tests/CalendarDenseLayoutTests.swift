import XCTest
@testable import hidigFocus

final class CalendarDenseLayoutTests: XCTestCase {
    func testDurationIsTheOnlySourceOfHeightAtBothSavedScales() {
        let task = ManagedTask(title: String(repeating: "Длинное название ", count: 40))
        for hour in [96.0, 120.0] {
            for minutes in [15.0, 30.0, 45.0, 60.0] {
                let item = CalendarDenseItem(task: task, interval: PlannerInterval(id: task.id.uuidString, start: 540, end: 540 + minutes), placement: PlannerPlacement(lane: 0, laneCount: 1), width: 200, hourHeight: hour)
                XCTAssertEqual(item.rect.height, minutes / 60 * hour)
                XCTAssertEqual(item.rect.minY, 9 * hour)
            }
        }
    }
    func testDenseOverlapsRetainEveryIdentityAndHavePositiveFrames() {
        let tasks = (0..<500).map { ManagedTask(title: "Задача \($0)") }
        let slots = tasks.map { PlannerInterval(id: $0.id.uuidString, start: 540, end: 570) }
        let placements = PlannerLayout.placements(slots)
        let items = zip(tasks, slots).map { task, slot in CalendarDenseItem(task: task, interval: slot, placement: placements[slot.id]!, width: 76, hourHeight: 96) }
        XCTAssertEqual(Set(items.map(\.id)), Set(tasks.map(\.id)))
        XCTAssertTrue(items.allSatisfy { $0.rect.width >= 1 && $0.rect.height == 48 && $0.rect.origin.x.isFinite })
        XCTAssertEqual(items.count, 500)
    }
    func testHitRegionsKeepCompletionSeparateFromResizeAndThinCardsOpenDetails() {
        let task = ManagedTask(title: "Проверка")
        let item = CalendarDenseItem(task: task, rect: CGRect(x: 10, y: 20, width: 180, height: 72))
        XCTAssertEqual(CalendarDenseLayout.hit(CGPoint(x: 20, y: 30), items: [item])?.part, .completion)
        XCTAssertEqual(CalendarDenseLayout.hit(CGPoint(x: 80, y: 22), items: [item])?.part, .start)
        XCTAssertEqual(CalendarDenseLayout.hit(CGPoint(x: 80, y: 90), items: [item])?.part, .end)
        XCTAssertEqual(CalendarDenseLayout.hit(CGPoint(x: 80, y: 50), items: [item])?.part, .body)
        XCTAssertNil(CalendarDenseLayout.hit(CGPoint(x: 200, y: 50), items: [item]))
        let thin = CalendarDenseItem(task: task, rect: CGRect(x: 10, y: 20, width: 2, height: 72))
        XCTAssertEqual(CalendarDenseLayout.hit(CGPoint(x: 11, y: 22), items: [thin])?.part, .body)
    }
    func testPainterOrderDeterminesHitWithoutChangingData() {
        let first = ManagedTask(title: "Первая"), last = ManagedTask(title: "Последняя")
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let items = [CalendarDenseItem(task: first, rect: rect), CalendarDenseItem(task: last, rect: rect)]
        XCTAssertEqual(CalendarDenseLayout.hit(CGPoint(x: 50, y: 30), items: items)?.id, last.id)
        XCTAssertEqual(items.first?.task, first)
    }
    func testTypographyFittingIsBoundedAndDoesNotMutateOriginalText() {
        let original = "Длинное русское название задачи, которое нужно прочитать в карточке полностью"
        let font = NSFont.systemFont(ofSize: 13)
        let lines = CalendarCanvasText.lines(original, width: 90, font: font, limit: 3)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.last!.hasSuffix("…"))
        XCTAssertTrue(lines.allSatisfy { ($0 as NSString).size(withAttributes: [.font: font]).width <= 90 })
        XCTAssertEqual(CalendarCanvasText.lines(original, width: 90, font: font, limit: 3), lines)
        XCTAssertEqual(original, "Длинное русское название задачи, которое нужно прочитать в карточке полностью")
    }
    func testEmbeddedConfigurationCannotActivateForProductionOrForeignBundle() {
        let config = ["HIDIGFOCUS_QA": "1", "HIDIGFOCUS_DATA_DIR": "/tmp/synthetic", "SECRET": "never-import"]
        XCTAssertTrue(HidigRuntime.qaEnvironment(bundleID: "com.hidig.focus", configuration: config).isEmpty)
        XCTAssertTrue(HidigRuntime.qaEnvironment(bundleID: "other.qa", configuration: config).isEmpty)
        XCTAssertTrue(HidigRuntime.qaEnvironment(bundleID: nil, configuration: config).isEmpty)
        let values = HidigRuntime.qaEnvironment(bundleID: "com.hidig.focus.calendar.candidate.qa", configuration: config)
        XCTAssertEqual(values["HIDIGFOCUS_QA"], "1")
        XCTAssertNil(values["SECRET"])
        XCTAssertTrue(HidigRuntime.qaEnvironment(bundleID: "com.hidig.focus.calendar.candidate.qa", configuration: [:]).isEmpty)
    }
    func testDrawingSurfaceIsLimitedToRetainedViewportWithoutChangingEventGeometry() {
        let visible = CalendarVisibleMinutes(lower: 270, upper: 690)
        let slice = CalendarDenseLayout.drawingSlice(visible: visible, hourHeight: 120)
        XCTAssertEqual(slice.minY, 540)
        XCTAssertEqual(slice.height, 840)
        let task = ManagedTask(title: "Переход через границу")
        let item = CalendarDenseItem(task: task, interval: PlannerInterval(id: task.id.uuidString, start: 240, end: 360), placement: PlannerPlacement(lane: 0, laneCount: 1), width: 200, hourHeight: 120)
        XCTAssertEqual(item.rect.minY, 480)
        XCTAssertEqual(item.rect.height, 240)
        XCTAssertTrue(item.rect.maxY > slice.minY)
    }
    @MainActor func testNativeAccessibilityRetainsEveryEventAndActionsWithoutViewGraphs() throws {
        let tasks = (0..<500).map { ManagedTask(title: "Задача \($0)") }
        let items = tasks.map { CalendarDenseItem(task: $0, rect: CGRect(x: 0, y: 600, width: 2, height: 48)) }
        var opened: UUID?
        var completed: UUID?
        var adjusted: (UUID, Int)?
        let view = CalendarDenseAccessibilityView(frame: CGRect(x: 0, y: 0, width: 200, height: 2304))
        let component = CalendarDenseAccessibility(items: items, label: "Плотный день",
            name: { $0.title }, completionTitle: { _ in "Выполнить" },
            open: { opened = $0.id }, complete: { completed = $0.id },
            adjust: { adjusted = ($0.id, $1) })
        component.configure(view)
        XCTAssertTrue(view.isAccessibilityElement())
        XCTAssertEqual(view.accessibilityChildren()?.count, 500)
        XCTAssertTrue(view.elements.allSatisfy { $0.isAccessibilityEnabled() })
        XCTAssertEqual(Set(view.elements.map(\.taskID)), Set(tasks.map(\.id)))
        let target = try XCTUnwrap(view.elements.last)
        XCTAssertTrue(target.accessibilityPerformPress())
        XCTAssertEqual(opened, tasks.last?.id)
        let actions = try XCTUnwrap(target.accessibilityCustomActions())
        XCTAssertEqual(actions.map(\.name), ["Выполнить", "Увеличить длительность на 15 минут", "Уменьшить длительность на 15 минут"])
        XCTAssertEqual(actions[0].handler?(), true)
        XCTAssertEqual(completed, tasks.last?.id)
        XCTAssertEqual(actions[1].handler?(), true)
        XCTAssertEqual(adjusted?.0, tasks.last?.id); XCTAssertEqual(adjusted?.1, 15)
        XCTAssertEqual(actions[2].handler?(), true)
        XCTAssertEqual(adjusted?.1, -15)
        component.configure(view)
        XCTAssertTrue(view.elements.last === target, "Retain stable accessibility identity across redraws")
        var changed = try XCTUnwrap(tasks.last)
        changed.title = "Изменённое название"
        let updated = CalendarDenseAccessibility(items: [CalendarDenseItem(task: changed, rect: CGRect(x: 10, y: 700, width: 100, height: 90))], label: "Плотный день", name: { $0.title }, completionTitle: { _ in "Вернуть в активные" }, open: { opened = $0.id }, complete: { completed = $0.id }, adjust: { adjusted = ($0.id, $1) })
        weak var removed = view.elements.first
        updated.configure(view)
        XCTAssertEqual(view.elements.count, 1)
        XCTAssertNil(removed, "Filtered occurrences must release their native elements")
        XCTAssertTrue(view.elements.first === target)
        XCTAssertEqual(target.accessibilityLabel(), changed.title)
        XCTAssertEqual(target.rect.minY, 700)
        XCTAssertEqual(target.accessibilityFrameInParentSpace(), target.rect)
        XCTAssertEqual(target.accessibilityCustomActions()?.first?.name, "Вернуть в активные")
        let empty = CalendarDenseAccessibility(items: [], label: "Пусто", name: { $0.title }, completionTitle: { _ in "Выполнить" }, open: { _ in }, complete: { _ in }, adjust: { _, _ in })
        empty.configure(view)
        XCTAssertTrue(view.elements.isEmpty)
    }
    @MainActor func testNativeAccessibilityVisibleChildrenFollowTheClipWithoutDroppingRetainedIdentities() {
        let before = ManagedTask(title: "До окна"), inside = ManagedTask(title: "В окне")
        let component = CalendarDenseAccessibility(items: [
            CalendarDenseItem(task: before, rect: CGRect(x: 0, y: 600, width: 2, height: 48)),
            CalendarDenseItem(task: inside, rect: CGRect(x: 0, y: 1000, width: 2, height: 48))], label: "День",
            name: { $0.title }, completionTitle: { _ in "Выполнить" }, open: { _ in }, complete: { _ in }, adjust: { _, _ in })
        let clip = NSClipView(frame: CGRect(x: 0, y: 0, width: 200, height: 338))
        let view = CalendarDenseAccessibilityView(frame: CGRect(x: 0, y: 0, width: 200, height: 2304))
        clip.documentView = view
        component.configure(view)
        clip.scroll(to: CGPoint(x: 0, y: 900))
        XCTAssertEqual(view.accessibilityChildren()?.count, 2)
        let visible = view.accessibilityVisibleChildren() as? [CalendarDenseAccessibilityElement]
        XCTAssertEqual(visible?.map(\.taskID), [inside.id])
        clip.scroll(to: CGPoint(x: 0, y: 500))
        XCTAssertEqual((view.accessibilityVisibleChildren() as? [CalendarDenseAccessibilityElement])?.map(\.taskID), [before.id])
        XCTAssertEqual(view.accessibilityChildren()?.count, 2)
    }
    func testRendererSelectionRetainsOrdinaryCardsAndCanBeComparedInQA() {
        XCTAssertFalse(CalendarDenseLayout.usesCanvas(taskCount: 160))
        XCTAssertTrue(CalendarDenseLayout.usesCanvas(taskCount: 161))
        XCTAssertFalse(CalendarDenseLayout.usesCanvas(taskCount: 10000, override: "legacy"))
        XCTAssertTrue(CalendarDenseLayout.usesCanvas(taskCount: 1, override: "canvas"))
    }
}
