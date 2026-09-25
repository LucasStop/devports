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
                Divider()
                SessionBarView(store: store, session: session)
            } else {
                ActionsLog(entries: store.log)
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        // The Dock icon and ⌘Tab only while this window is open; the app is menu-bar only otherwise.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            store.isTerminalOpen = true
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
            store.isTerminalOpen = false
        }
        .task {
            while !Task.isCancelled {
                terminal.poll(processes: store.processes)
                try? await Task.sleep(for: .seconds(1))
            }
        }
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
        case .running: .ok
        case .exited(let code) where code == 0: .idle
        case .exited: .danger
        }
    }
}

private struct SessionView: NSViewRepresentable {
    let session: TerminalSessions.Session

    func makeNSView(context: Context) -> LocalProcessTerminalView { session.view }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
}

/// Under each tab: what its shell is running, on which port, for how long, and how to stop or rerun it.
private struct SessionBarView: View {
    let store: Store
    let session: TerminalSessions.Session

    var body: some View {
        // Ticks each second for "há 2 min" and for Forçar, which appears 5 s after Parar.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                content(now: context.date)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 34)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch session.bar {
        case .running(let job, let ports):
            led(.ok)
            Text("rodando").foregroundStyle(.primary)
            Text("· \(job.command) · pid \(job.pid)").truncationMode(.middle)
            ForEach(ports, id: \.number) { port in
                Text(":\(port.number)").monospacedDigit()
                if port.isExposed { Badge(text: "REDE", color: .warning, textColor: .warningText) }
            }
            Text("· há \(Format.uptime(now.timeIntervalSince(job.startedAt)))")
            Spacer(minLength: 8)
            if let port = ports.first {
                Button("Abrir :\(port.number)") { store.openInBrowser(port.number) }
            }
            Button("Reiniciar") { store.restartJob(in: session) }
            Button("Parar", role: .destructive) { store.stopJob(in: session) }.tint(.danger)
        case .stopping(let job, let since):
            let waited = now.timeIntervalSince(since)
            led(.warning)
            Text("parando").foregroundStyle(.primary)
            Text("· \(job.command) · pid \(job.pid)").truncationMode(.middle)
            Text(waited < 5 ? "· aguardando \(Int(5 - waited)) s" : "· não respondeu em 5 s")
            Spacer(minLength: 8)
            if waited >= 5 {
                Button("Forçar", role: .destructive) { store.forceJob(in: session) }.tint(.danger)
            }
        case .finished(let finished):
            led(.idle)
            Text("terminou").foregroundStyle(.primary)
            Text("· \(finished.command) · durou \(Format.uptime(finished.duration))").truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Rodar de novo") { store.restartJob(in: session) }
        case .idle:
            led(.idle)
            Text("zsh").foregroundStyle(.primary)
            Text("· \(session.folder)").truncationMode(.head)
            Spacer(minLength: 8)
            Button("Mostrar no Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: session.folder)) }
        case .shellExited(let code):
            led(code == 0 ? .idle : .danger)
            Text(code.map { "shell encerrado com código \($0)" } ?? "shell encerrado").foregroundStyle(.primary)
            Spacer()
        }
    }

    private func led(_ color: SwiftUI.Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
    }
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
