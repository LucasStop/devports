import SwiftTerm
import SwiftUI

/// Tabs: the fixed "Ações" log, then one per shell session.
struct TerminalWindow: View {
    let store: Store
    let terminal: TerminalSessions

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()
            if let session = terminal.sessions.first(where: { $0.id == terminal.selected }) {
                SessionView(session: session).id(session.id)
            } else {
                ActionsLog(entries: store.log)
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        // The Dock icon and ⌘Tab only while this window is open; the app is menu-bar only otherwise.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                tab(isSelected: terminal.selected == nil, select: { terminal.selected = nil }) {
                    Image(systemName: "list.bullet")
                    Text("Ações")
                }
                ForEach(terminal.sessions) { session in
                    tab(isSelected: terminal.selected == session.id, select: { terminal.selected = session.id }) {
                        Circle().fill(color(session.status)).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(session.title).lineLimit(1)
                        Button {
                            terminal.close(session)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(
                                width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Fechar \(session.title)")
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
    }

    private func tab<Label: View>(isSelected: Bool, select: @escaping () -> Void, @ViewBuilder label: () -> Label)
        -> some View
    {
        HStack(spacing: 6) { label() }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isSelected ? SwiftUI.Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .onTapGesture(perform: select)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Green running, gray exited clean, red exited with an error (DESIGN.md).
    private func color(_ status: TerminalSessions.Session.Status) -> SwiftUI.Color {
        switch status {
        case .running: .green
        case .exited(let code) where code == 0: .gray
        case .exited: .red
        }
    }
}

private struct SessionView: NSViewRepresentable {
    let session: TerminalSessions.Session

    func makeNSView(context: Context) -> LocalProcessTerminalView { session.view }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
}

private struct ActionsLog: View {
    let entries: [Store.LogEntry]

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "Nenhuma ação ainda", systemImage: "list.bullet",
                description: Text("Encerrar, abrir e rodar scripts pelo DevPorts aparece aqui."))
        } else {
            List(entries.reversed()) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.date, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
                    Text(entry.command).textSelection(.enabled)
                    Spacer()
                    Text(entry.result).foregroundStyle(.secondary)
                }
                .font(.system(size: 12, design: .monospaced))
            }
        }
    }
}
