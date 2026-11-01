import XCTest
@testable import hidigFocus

final class TaskListPickerTests: XCTestCase {
    func testSidebarOrderAndEveryListArePreservedExactlyOnce() {
        let second = TaskFolder(name: "Second", sortOrder: 20)
        let first = TaskFolder(name: "First", sortOrder: 10)
        let missingFolderID = UUID()
        let nestedA = TaskList(folderID: first.id, name: "Same name", sortOrder: 40)
        let nestedB = TaskList(folderID: first.id, name: "Same name", sortOrder: 80)
        let other = TaskList(folderID: second.id, name: "Other", sortOrder: 1)
        let loose = TaskList(name: "Loose", sortOrder: 50)
        let orphan = TaskList(folderID: missingFolderID, name: "Orphan", sortOrder: 60)
        let ordered = [other, .inbox, nestedA, loose, orphan, nestedB]
        let model = TaskListPickerContents(orderedFolders: [first, second], orderedLists: ordered)
        XCTAssertEqual(model.folders.map(\.id), [first.id, second.id])
        XCTAssertEqual(model.folders[0].lists.map(\.id), [nestedA.id, nestedB.id])
        XCTAssertEqual(model.folders[1].lists.map(\.id), [other.id])
        XCTAssertEqual(model.unfiled.map(\.id), [TaskList.inboxID, loose.id, orphan.id])
        let all = model.folders.flatMap(\.lists) + model.unfiled
        XCTAssertEqual(all.count, ordered.count)
        XCTAssertEqual(Set(all.map(\.id)), Set(ordered.map(\.id)))
    }

    func testOnlySelectedFolderOpensWithoutChangingSidebarPreferences() {
        let selectedFolder = TaskFolder(name: "Selected", isCollapsed: true)
        let otherFolder = TaskFolder(name: "Other", isCollapsed: false)
        let selected = TaskList(folderID: selectedFolder.id, name: "Selected list")
        let other = TaskList(folderID: otherFolder.id, name: "Other list")
        let folders = [selectedFolder, otherFolder]
        let model = TaskListPickerContents(orderedFolders: folders, orderedLists: [selected, other, .inbox])
        XCTAssertEqual(model.initiallyExpandedFolders(selection: selected.id), [selectedFolder.id])
        XCTAssertEqual(model.initiallyExpandedFolders(selection: other.id), [otherFolder.id])
        XCTAssertTrue(model.initiallyExpandedFolders(selection: TaskList.inboxID).isEmpty)
        XCTAssertTrue(model.initiallyExpandedFolders(selection: UUID()).isEmpty)
        XCTAssertEqual(model.folders.map(\.folder), folders)
    }

    func testInboxRemainsReachableAndEmptyFoldersAreRetained() {
        let empty = TaskFolder(name: "Empty")
        var inbox = TaskList.inbox; inbox.folderID = empty.id
        let model = TaskListPickerContents(orderedFolders: [empty], orderedLists: [inbox])
        XCTAssertEqual(model.folders.map(\.id), [empty.id])
        XCTAssertTrue(model.folders[0].lists.isEmpty)
        XCTAssertEqual(model.unfiled.map(\.id), [TaskList.inboxID])
        XCTAssertTrue(model.initiallyExpandedFolders(selection: TaskList.inboxID).isEmpty)
        let noFolders = TaskListPickerContents(orderedFolders: [], orderedLists: [inbox])
        XCTAssertEqual(noFolders.unfiled.map(\.id), [TaskList.inboxID])
    }
}
