import SwiftUI

struct SyncButton: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var integration: IntegrationState
    @EnvironmentObject private var store: AppStore
    var showTitle = true

    @State private var rotation = 0.0

    var body: some View {
        Button {
            Task { await store.checkTickTickImportConnection() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
                if showTitle {
                    Text(integration.isSynchronizing ? "Проверяем" : "Проверить доступ для импорта")
                }
            }
        }
        .buttonStyle(showTitle ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(HidigIconButtonStyle()))
        .disabled(integration.isSynchronizing)
        .help(syncHelp)
        .onAppear { updateRotation(integration.isSynchronizing) }
        .onChange(of: integration.isSynchronizing) { updateRotation($0) }
        .onChange(of: reduceMotion) { _ in updateRotation(integration.isSynchronizing) }
    }

    private var syncHelp: String {
        integration.isSynchronizing ? "Проверяем доступ к импорту" : "Проверить доступ к TickTick для импорта"
    }

    private func updateRotation(_ isSynchronizing: Bool) {
        if reduceMotion {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { rotation = 0 }
            return
        }
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
