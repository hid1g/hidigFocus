import SwiftUI

struct SyncButton: View {
    @EnvironmentObject private var store: AppStore
    var showTitle = true

    @State private var rotation = 0.0

    var body: some View {
        Button {
            Task { await store.refreshConnectionAndTasks() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(rotation))
                if showTitle {
                    Text(store.isSynchronizing ? "Обновляем" : "Обновить")
                }
            }
        }
        .buttonStyle(showTitle ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(HidigIconButtonStyle()))
        .disabled(store.isSynchronizing)
        .help(syncHelp)
        .onAppear { updateRotation(store.isSynchronizing) }
        .onChange(of: store.isSynchronizing) { updateRotation($0) }
    }

    private var syncHelp: String {
        if store.isSynchronizing { return "Идёт синхронизация TickTick" }
        if let date = store.state.lastSuccessfulSync {
            return "Последняя синхронизация: \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Синхронизировать TickTick"
    }

    private func updateRotation(_ isSynchronizing: Bool) {
        if isSynchronizing {
            rotation = 0
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                rotation = 0
            }
        }
    }
}

private struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}
