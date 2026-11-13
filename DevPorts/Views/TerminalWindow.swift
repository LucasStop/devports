import SwiftTerm
import SwiftUI

/// The separate Terminal window: the same sessions as the popover tab, hosted here.
struct TerminalWindow: View {
    let store: Store
    let terminal: TerminalSessions

    var body: some View {
        TerminalContent(store: store, terminal: terminal, host: .window)
            .frame(minWidth: 640, minHeight: 360)
            // The Dock icon and ⌘Tab only while this window is open; the app is menu-bar only otherwise.
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
                store.isTerminalOpen = true
                terminal.host = .window
            }
            .onDisappear {
                NSApp.setActivationPolicy(.accessory)
                store.isTerminalOpen = false
                terminal.host = .popover
            }
    }
}

/// Tabs: the fixed "Ações" log, then one per shell session. Shared by the window and the popover tab (`compact`).
struct TerminalContent: View {
    let store: Store
    let terminal: TerminalSessions
    let host: TerminalSessions.Host
    var compact = false
    /// Height of the terminal area; nil fills what the host leaves.
    var terminalHeight: CGFloat?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("terminalHost") private var placement = TerminalSessions.Host.popover

    var body: some View {
        if terminal.host != host {
            notice
        } else {
            VStack(spacing: 0) {
                tabs
                Divider()
                if let session = terminal.sessions.first(where: { $0.id == terminal.selected }) {
                    SessionView(session: session).id(session.id)
                        .frame(minHeight: terminalHeight, maxHeight: terminalHeight ?? .infinity)
                    Divider()
                    SessionBarView(store: store, session: session, compact: compact)
                } else if compact && terminal.sessions.isEmpty && store.log.isEmpty {
                    placeholder("Nenhuma sessão", "Rode um script de um projeto ou abra um shell.", "Nova sessão") {
                        newSession()
                    }
                } else {
                    ActionsLog(entries: store.log)
                        .frame(minHeight: terminalHeight, maxHeight: terminalHeight ?? .infinity)
                }
            }
            .task {
                while !Task.isCancelled {
                    terminal.poll(processes: store.processes)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    /// The other host has the sessions; bringing them back ends nothing.
    private var notice: some View {
        switch host {
        case .popover:
            placeholder(
                "Sessões abertas na janela",
                "O terminal está na janela separada. Trazer de volta não encerra nada.", "Trazer para o popover"
            ) {
                terminal.host = .popover
                dismissWindow(id: "terminal")
            }
        case .window:
            placeholder(
                "Sessões abertas no popover",
                "O terminal está na aba do popover. Trazer de volta não encerra nada.", "Trazer para a janela"
            ) {
                terminal.host = .window
            }
        }
    }

    private func placeholder(_ title: String, _ detail: String, _ button: String, action: @escaping () -> Void)
        -> some View
    {
        VStack(spacing: 8) {
            Text(title).fontWeight(.semibold)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(SmallButtonStyle(color: .ok, filled: true))
        }
        .font(.system(size: 12))
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: terminalHeight, maxHeight: terminalHeight ?? .infinity)
    }

    private func newSession() {
        terminal.open(title: "zsh", folder: NSHomeDirectory())
    }

    private func openInWindow() {
        terminal.host = .window
        openWindow(id: "terminal")
    }

    /// Window button and ⋯ menu, only in the popover tab.
    private var popoverActions: some View {
        HStack(spacing: 2) {
            IconButton(systemName: "macwindow", label: "Abrir em janela", action: openInWindow)
            Menu {
                Picker("Abrir Terminal em", selection: $placement) {
                    Text("Popover").tag(TerminalSessions.Host.popover)
                    Text("Janela").tag(TerminalSessions.Host.window)
                }
                .pickerStyle(.inline)
                Divider()
                Button("Nova sessão", action: newSession)
                Button("Abrir em janela agora", action: openInWindow)
            } label: {
                Image(systemName: "ellipsis").frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Mais opções do Terminal")
        }
        .padding(.trailing, 6)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tabList
            if compact { popoverActions }
        }
        .frame(height: 36)
    }

    private var tabList: some View {
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

/// Under each tab: what its shell is running, on which port, for how long, and how to stop or rerun it. `compact`
/// (the popover, 440 pt) puts the buttons on a second line.
private struct SessionBarView: View {
    let store: Store
    let session: TerminalSessions.Session
    var compact = false

    var body: some View {
        // Ticks each second for "há 2 min" and for Forçar, which appears 5 s after Parar.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) { info(now: context.date) }
                        HStack(spacing: 8) { buttons(now: context.date) }
                    }
                    .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 10))
                } else {
                    HStack(spacing: 8) {
                        info(now: context.date)
                        Spacer(minLength: 8)
                        buttons(now: context.date)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .frame(height: 34)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private func info(now: Date) -> some View {
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
        case .stopping(let job, let since):
            let waited = now.timeIntervalSince(since)
            led(.warning)
            Text("parando").foregroundStyle(.primary)
            Text("· \(job.command) · pid \(job.pid)").truncationMode(.middle)
            Text(waited < 5 ? "· aguardando \(Int(5 - waited)) s" : "· não respondeu em 5 s")
        case .finished(let finished):
            led(.idle)
            Text("terminou").foregroundStyle(.primary)
            Text("· \(finished.command) · durou \(Format.uptime(finished.duration))").truncationMode(.middle)
        case .idle:
            led(.idle)
            Text("zsh").foregroundStyle(.primary)
            Text("· \(session.folder)").truncationMode(.head)
        case .shellExited(let code):
            led(code == 0 ? .idle : .danger)
            Text(code.map { "shell encerrado com código \($0)" } ?? "shell encerrado").foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func buttons(now: Date) -> some View {
        switch session.bar {
        case .running(_, let ports):
            if let port = ports.first {
                Button("Abrir :\(port.number)") { store.openInBrowser(port.number) }
            }
            Button("Reiniciar") { store.restartJob(in: session) }
            Button("Parar", role: .destructive) { store.stopJob(in: session) }.tint(.danger)
        case .stopping(_, let since):
            if now.timeIntervalSince(since) >= 5 {
                Button("Forçar", role: .destructive) { store.forceJob(in: session) }.tint(.danger)
            }
        case .finished:
            Button("Rodar de novo") { store.restartJob(in: session) }
        case .idle:
            Button("Mostrar no Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: session.folder)) }
        case .shellExited:
            EmptyView()
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
                    Text(entry.command).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(entry.result).foregroundStyle(.secondary)
                }
                .font(.system(size: 12, design: .monospaced))
            }
        }
    }
}
