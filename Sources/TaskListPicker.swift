import SwiftUI

/// Inputs use the same ordering as the task sidebar. Grouping never writes folder
/// disclosure preferences or changes a task; only an explicit list choice does.
struct TaskListPickerContents {
    struct FolderSection: Identifiable {
        let folder: TaskFolder
        let lists: [TaskList]
        var id: UUID { folder.id }
    }

    let folders: [FolderSection]
    let unfiled: [TaskList]

    init(orderedFolders: [TaskFolder], orderedLists: [TaskList]) {
        let folderIDs = Set(orderedFolders.map(\.id))
        var grouped: [UUID: [TaskList]] = [:]
        var loose: [TaskList] = []
        for list in orderedLists {
            if list.id != TaskList.inboxID, let folderID = list.folderID, folderIDs.contains(folderID) {
                grouped[folderID, default: []].append(list)
            } else {
                // Keep Inbox and lists with a missing folder reachable as well.
                loose.append(list)
            }
        }
        folders = orderedFolders.map { FolderSection(folder: $0, lists: grouped[$0.id] ?? []) }
        unfiled = loose
    }

    func initiallyExpandedFolders(selection: UUID) -> Set<UUID> {
        Set(folders.filter { $0.lists.contains { $0.id == selection } }.map(\.id))
    }
}

struct TaskListPicker: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let folders: [TaskFolder]
    let lists: [TaskList]
    @Binding var selection: UUID
    @Binding var isPresented: Bool
    @State private var expandedFolders: Set<UUID> = []

    private var contents: TaskListPickerContents {
        TaskListPickerContents(orderedFolders: folders, orderedLists: lists)
    }
    private var selected: TaskList? { lists.first { $0.id == selection } }

    var body: some View {
        Button {
            if !isPresented { expandedFolders = contents.initiallyExpandedFolders(selection: selection) }
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet").frame(width: 15)
                Text(selected?.name ?? "Выбрать список")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(HidigPalette.secondary)
            }
            .hidigFont(size: 12)
            .padding(.horizontal, 6)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(selected?.name ?? "Выбрать список")
        .accessibilityLabel("Список задачи")
        .accessibilityValue(selected?.name ?? "Не выбран")
        .accessibilityIdentifier("task.listPicker")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            TaskListPickerMenu(contents: contents, selection: selection, expandedFolders: $expandedFolders) { id in
                selection = id
                isPresented = false
            }
            .onExitCommand { isPresented = false }
        }
    }
}

/// Separate content also permits a native preview without opening a task editor.
struct TaskListPickerMenu: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let contents: TaskListPickerContents
    let selection: UUID
    @Binding var expandedFolders: Set<UUID>
    let select: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(contents.folders) { section in
                    DisclosureGroup(isExpanded: Binding(
                        get: { expandedFolders.contains(section.id) },
                        set: { expanded in
                            if expanded { expandedFolders.insert(section.id) }
                            else { expandedFolders.remove(section.id) }
                        }
                    )) {
                        VStack(spacing: 3) {
                            if section.lists.isEmpty {
                                Text("В папке нет списков")
                                    .hidigFont(size: 11)
                                    .foregroundStyle(HidigPalette.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                                    .padding(.horizontal, 11)
                            } else {
                                ForEach(section.lists) { list in listButton(list) }
                            }
                        }
                    } label: {
                        Text(section.folder.name)
                            .hidigFont(size: 12, weight: .medium)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                            .help(section.folder.name)
                    }
                    .accessibilityIdentifier("task.listPicker.folder.\(section.id.uuidString)")
                }
                if !contents.folders.isEmpty && !contents.unfiled.isEmpty { Divider().padding(.vertical, 4) }
                ForEach(contents.unfiled) { list in listButton(list) }
                if contents.folders.isEmpty && contents.unfiled.isEmpty {
                    Text("Нет доступных списков")
                        .hidigFont(size: 12)
                        .foregroundStyle(HidigPalette.secondary)
                        .padding(11)
                }
            }
            .padding(7)
        }
        .frame(width: 280)
        .frame(maxHeight: 340)
        .background(HidigPalette.surface)
        .foregroundStyle(HidigPalette.forest)
    }

    private func listButton(_ list: TaskList) -> some View {
        let isSelected = list.id == selection
        return Button { select(list.id) } label: {
            HStack(spacing: 9) {
                Image(systemName: list.id == TaskList.inboxID ? "tray" : (list.isPinned ? "pin.fill" : "list.bullet"))
                    .frame(width: 16)
                Text(list.name).lineLimit(1)
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(HidigPalette.controlFill)
                        .accessibilityHidden(true)
                }
            }
            .hidigFont(size: 12, weight: isSelected ? .semibold : .regular)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(isSelected ? HidigPalette.lettuce.opacity(0.55) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(list.name)
        .accessibilityLabel(list.name)
        .accessibilityValue(isSelected ? "Выбранный список" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("task.listPicker.option.\(list.id.uuidString)")
    }
}
