import AppKit
import SwiftUI

extension TaskPriority {
    var accent: Color {
        switch self {
        case .none: return HidigPalette.secondary
        case .low: return Color(nsColor: .systemBlue)
        case .medium:
            return Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#E9BF51") : NSColor(hex: "#AC790E")
            })
        case .high: return Color(nsColor: .systemRed)
        }
    }
}

struct TaskPriorityBorder: ViewModifier {
    let priority: TaskPriority
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay {
            if priority != .none {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(priority.accent, lineWidth: priority == .high ? 1.8 : 1.3)
                    .allowsHitTesting(false)
            }
        }
    }
}
extension View {
    func taskPriorityBorder(_ priority: TaskPriority, radius: CGFloat) -> some View {
        modifier(TaskPriorityBorder(priority: priority, radius: radius))
    }
}

struct TaskCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 9) {
                HidigCheckmarkBox(isChecked: configuration.isOn, size: 18).accessibilityHidden(true)
                configuration.label.hidigFont(size: 13)
            }.contentShape(Rectangle()).frame(minHeight: 28)
        }.buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? "Отмечено" : "Не отмечено")
    }
}

struct TaskSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 12)
                    Text(title).hidigFont(size: 12, weight: .medium)
                    Spacer()
                }.foregroundStyle(HidigPalette.secondary).frame(minHeight: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(expanded ? "Развёрнуто" : "Свёрнуто")
            if expanded { content().padding(.leading, 19) }
        }
    }
}

struct TaskPriorityPicker: View {
    @Binding var priority: TaskPriority
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: priority == .none ? "flag" : "flag.fill")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(priority.accent)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Приоритет: \(priority.title)")
            .accessibilityLabel("Приоритет: \(priority.title)")
            .popover(isPresented: $presented) {
                VStack(spacing: 3) {
                    ForEach(TaskPriority.allCases) { value in
                        Button { priority = value; presented = false } label: {
                            HStack(spacing: 10) {
                                Image(systemName: value == .none ? "flag" : "flag.fill").foregroundStyle(value.accent).frame(width: 16)
                                Text(value.title).hidigFont(size: 13)
                                Spacer()
                                if value == priority { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                            }.padding(9).frame(width: 180).contentShape(Rectangle())
                                .background(value == priority ? HidigPalette.hover : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }.padding(7).background(HidigPalette.surface)
            }
    }
}
