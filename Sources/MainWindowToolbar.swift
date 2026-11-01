import SwiftUI

enum MainWindowHeading {
    static func date(_ date: Date, calendar: Calendar = PlannerCalendar.current) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .omitted,
                                       locale: Locale(identifier: "ru_RU"),
                                       calendar: calendar, timeZone: calendar.timeZone))
    }
}

/// Only this small title observes the planner, not the entire navigation shell.
struct MainWindowToolbarTitle: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: PlannerWorkspace

    var body: some View {
        Text((store.selectedSection == .calendar || store.selectedSection == .tasks) && workspace.presentation == .calendar
             ? MainWindowHeading.date(workspace.anchor) : store.selectedSection.title)
            .hidigFont(size: 18, weight: .semibold)
            .foregroundStyle(HidigPalette.forest)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, 12)
            .padding(.trailing, 18)
            .padding(.vertical, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

struct TaskHierarchyDisclosure: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .frame(width: PrintTokens.buttonHeight, height: PrintTokens.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(HidigIconButtonStyle())
        .accessibilityLabel(isExpanded ? "Свернуть подзадачи" : "Развернуть подзадачи")
        .accessibilityValue(isExpanded ? "Развернуто" : "Свернуто")
        .help(isExpanded ? "Свернуть подзадачи" : "Развернуть подзадачи")
    }
}
