import SwiftUI

/// The menu bar popover: dev ports first, then dev processes without a port, grouped by project (DESIGN.md).
struct PopoverView: View {
    let store: Store
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @AppStorage("showSystem") private var showSystem = false
    @State private var listHeight: CGFloat = 0
    /// The row or group waiting on its inline "Encerrar" confirmation.
    @State private var confirming: String?
    @State private var confirmingQuit = false
    @State private var showSettings = false
    @AppStorage("popoverSizes") private var sizes = PopoverSizes()
    @AppStorage("terminalHost") private var placement = TerminalSessions.Host.popover
    @Environment(\.openWindow) private var openWindow

    private var tab: PopoverTab {
        get { store.tab }
        nonmutating set { store.tab = newValue }
    }

    /// The MenuBarExtra rebuilds this view on every scan (the label counts ports), so only previews pass `startOn`;
    /// writing a default here sent the popover back to Portas every 5 s.
    init(store: Store, startOn tab: PopoverTab? = nil) {
        self.store = store
        if let tab { store.tab = tab }
    }

    /// The Terminal tab has no search, no system toggle and no height cap of its own.
    private var size: PanelSize {
        showSettings ? PanelSize() : sizes.size(for: tab, terminalHost: placement)
    }

    /// DESIGN.md caps the popover at 660 pt; tab row, search field and footer take 129 of them.
    private static let maxListHeight: CGFloat = 531

    var body: some View {
        let overview = Overview(
            processes: store.processes, query: query, showSystem: showSystem,
            isPortTaken: ProcessScanner.isPortTaken)
        VStack(spacing: 0) {
            if showSettings {
                AjustesView(sizes: $sizes, placement: $placement) { showSettings = false }
            } else {
                content(overview)
            }
            if let banner = store.banner { errorBanner(banner) }
            if confirmingQuit { quitBand }
            if let pending = store.pendingRestart { restartBand(pending.process, command: pending.plan.command) }
            if size.height != nil { Spacer(minLength: 0) }
            Divider()
            footer(hiddenCount: tab == .ports ? overview.hiddenCount : nil)
        }
        .frame(width: size.width, height: size.height.map { CGFloat($0) }, alignment: .top)
        .onAppear {
            store.setPopoverOpen(true)
            store.isAppsTabOpen = tab == .apps
        }
        .onDisappear {
            store.setPopoverOpen(false)
            store.isAppsTabOpen = false
        }
        .onChange(of: tab) {
            store.isAppsTabOpen = tab == .apps
            // A port query means nothing to the Apps list, and the other way round.
            query = ""
        }
    }

    @ViewBuilder
    private func content(_ overview: Overview) -> some View {
        let fills = size.height != nil
        VStack(spacing: 0) {
            tabRow
            if tab != .terminal { searchField }
            if tab == .terminal {
                TerminalContent(
                    store: store, terminal: store.terminal, host: .popover, compact: true,
                    terminalHeight: fills ? nil : 300)
            } else if tab == .apps {
                AppsView(store: store, query: query, showSystem: showSystem, fills: fills)
            } else if overview.ports.isEmpty && overview.groups.isEmpty {
                emptyState(overview.searchedPort)
            } else {
                ScrollView {
                    list(overview).onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        listHeight = $0
                    }
                }
                // The window sizes to its content and a ScrollView has no height of its own, so it gets the list's,
                // up to the cap. An exact height also lets the popover shrink when a search leaves fewer rows.
                .frame(height: fills ? nil : min(listHeight, Self.maxListHeight))
                .frame(maxHeight: fills ? .infinity : nil)
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise").frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .keyboardShortcut("r")
        .help("Atualizar agora")
        .accessibilityLabel("Atualizar agora")
    }

    /// Always the top row: tabs, then refresh on the right. The search field sits right under it.
    private var tabRow: some View {
        HStack(spacing: 6) {
            tabPicker
            refreshButton
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 8, trailing: 8))
    }

    private var tabPicker: some View {
        HStack(spacing: 2) {
            ForEach(PopoverTab.allCases, id: \.self) { item in
                Button {
                    // Set to Janela, the tab opens the window and shows its notice; otherwise the sessions stay
                    // where they are, the window included.
                    if item == .terminal && placement == .window {
                        store.showTerminal(placement: .window) { openWindow(id: "terminal") }
                    } else {
                        tab = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? Color.primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(
                            tab == item ? Color(nsColor: .windowBackgroundColor) : .clear, in: .rect(cornerRadius: 6)
                        )
                        .shadow(color: .black.opacity(tab == item ? 0.12 : 0), radius: 1, y: 1)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(tab == .apps ? "Buscar app ou processo" : "Buscar porta, processo ou projeto", text: $query)
                .textFieldStyle(.plain)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 7))
        .padding(EdgeInsets(top: 0, leading: 12, bottom: 8, trailing: 12))
    }

    private func list(_ overview: Overview) -> some View {
        let showsPorts = !overview.ports.isEmpty || query.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            if showsPorts {
                sectionHeader("Portas", detail: "\(overview.ports.count)")
                if overview.ports.isEmpty {
                    Text("Nenhuma porta dev em uso")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                }
                ForEach(overview.ports) { PortRowView(row: $0, store: store, confirming: $confirming) }
            }
            if !overview.groups.isEmpty {
                if showsPorts {
                    Divider().padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                }
                let total = overview.groups.reduce(0) { $0 + $1.processes.count }
                sectionHeader(
                    "Processos dev", detail: "\(total) em \(counted(overview.groups.count, "grupo", "grupos"))")
                ForEach(overview.groups) { groupRows($0) }
            }
        }
        .padding(.bottom, 6)
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).fontWeight(.semibold)
            Text(detail)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(EdgeInsets(top: 6, leading: 14, bottom: 4, trailing: 14))
    }

    private func groupRows(_ group: Overview.ProcessGroup) -> some View {
        // A search opens every group, so matches inside them are not hidden behind a chevron.
        let isExpanded = !query.isEmpty || expanded.contains(group.name)
        let key = "group:\(group.name)"
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    expanded.formSymmetricDifference([group.name])
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(group.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(
                            counted(group.processes.count, "processo", "processos") + " · "
                                + Format.memory(group.memoryBytes)
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                    .frame(height: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "Aberto" : "Fechado")
                if isExpanded {
                    Button("Encerrar todos") { confirming = key }
                        .buttonStyle(SmallButtonStyle(color: .danger))
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, isExpanded ? 10 : 14)
            .contextMenu { groupMenu(group) }
            if confirming == key {
                let count = group.processes.count
                ConfirmBand(
                    text: count == 1
                        ? "Encerrar o processo de \(group.name)?" : "Encerrar os \(count) processos de \(group.name)?",
                    confirm: {
                        confirming = nil
                        store.terminate(group.processes)
                    },
                    cancel: { confirming = nil }
                )
                .padding(EdgeInsets(top: 2, leading: 14, bottom: 6, trailing: 14))
            }
            if isExpanded {
                ForEach(group.processes) { ProcessRowView(process: $0, store: store, confirming: $confirming) }
            }
        }
    }

    /// "Terminal na pasta" and, for a package.json project, its scripts run by the lockfile's manager.
    @ViewBuilder
    private func groupMenu(_ group: Overview.ProcessGroup) -> some View {
        if let folder = group.processes.lazy.compactMap({ $0.projectPath ?? $0.cwd }).first {
            Button("Terminal na pasta") {
                store.openTerminal(title: group.name, folder: folder)
                store.showTerminal { openWindow(id: "terminal") }
            }
            if let scripts = ProjectScripts.read(root: folder) {
                Menu("Scripts") {
                    ForEach(scripts.names, id: \.self) { name in
                        Button("\(scripts.manager) run \(name)") {
                            store.openTerminal(
                                title: "\(group.name) · \(name)", folder: folder,
                                command: "\(scripts.manager) run \(name)")
                            store.showTerminal { openWindow(id: "terminal") }
                        }
                    }
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                store.banner = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar aviso")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Color.danger)
        .padding(EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10))
        .background(Color.danger.opacity(0.07), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.danger.opacity(0.22)))
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 10, trailing: 12))
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private func emptyState(_ searchedPort: Overview.SearchedPort?) -> some View {
        if let port = searchedPort {
            VStack(spacing: 4) {
                HStack(spacing: 7) {
                    Led(color: port.isFree ? .ok : .warning)
                    Text("Porta \(String(port.number)) \(port.isFree ? "livre" : "em uso")")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(port.isFree ? "Nenhum processo escutando nela." : "Por um processo de outro usuário, como o root.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else if query.isEmpty {
            ContentUnavailableView {
                Label("Nenhuma porta dev em uso", image: .menuBarGlyph)
            } description: {
                Text("Servidores que você subir aparecem aqui.")
            }
        } else {
            ContentUnavailableView(
                "Nada encontrado", systemImage: "magnifyingglass",
                description: Text("Nenhuma porta, processo ou projeto com “\(query)”."))
        }
    }

    private func restartBand(_ process: DevProcess, command: String) -> some View {
        HStack(spacing: 8) {
            Text(
                "Reiniciar com \(Text(command).font(.system(size: 11.5, design: .monospaced))) em \(process.project ?? process.group)?"
            )
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Reiniciar") {
                Task { if await store.confirmRestart() { store.showTerminal { openWindow(id: "terminal") } } }
            }
            .buttonStyle(SmallButtonStyle(color: .ok, filled: true))
            Button("Cancelar") { store.cancelRestart() }.buttonStyle(SmallButtonStyle())
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(Color.ok.opacity(0.07), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ok.opacity(0.25)))
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 10, trailing: 12))
    }

    /// Quitting closes the ptys, which ends what the Terminal tabs started.
    private var quitBand: some View {
        let count = store.terminal.running.count
        return VStack(alignment: .leading, spacing: 10) {
            Text(
                count == 1
                    ? "1 sessão rodando no Terminal. Sair encerra essa sessão."
                    : "\(count) sessões rodando no Terminal. Sair encerra as \(count)."
            )
            .font(.system(size: 12))
            HStack(spacing: 8) {
                Spacer()
                Button("Cancelar") { confirmingQuit = false }.buttonStyle(SmallButtonStyle())
                Button("Sair e encerrar") {
                    store.terminal.closeAll()
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(SmallButtonStyle(color: .danger, filled: true))
            }
        }
        .padding(12)
    }

    private func footer(hiddenCount: Int?) -> some View {
        HStack(spacing: 8) {
            if tab != .terminal && !showSettings {
                Toggle(isOn: $showSystem) {
                    HStack(spacing: 8) {
                        Text("Mostrar sistema")
                        if let hiddenCount { Text(String(hiddenCount)).foregroundStyle(.secondary) }
                    }
                }
                .toggleStyle(.checkbox)
            }
            Spacer()
            Button("Ajustes") { showSettings.toggle() }
                .buttonStyle(SmallButtonStyle())
            Button("Sair") {
                if store.terminal.running.isEmpty { NSApplication.shared.terminate(nil) } else { confirmingQuit = true }
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}

private struct PortRowView: View {
    let row: Overview.PortRow
    let store: Store
    @Binding var confirming: String?

    var body: some View {
        let process = row.process
        let isStopping = store.stopping[process.pid] != nil
        HStack(spacing: 10) {
            Led(
                color: isStopping || !process.isDev || process.isSuspended ? .idle : row.port.isExposed ? .warning : .ok
            )
            HStack(spacing: 10) {
                Text(":" + String(row.port.number))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(process.label).font(.system(size: 13)).lineLimit(1)
                        if row.port.isExposed { Badge(text: "REDE", color: .warning, textColor: .warningText) }
                        if !process.isDev { Badge(text: "SISTEMA", color: .idle) }
                        if process.isSuspended { Badge(text: "SUSPENSO", color: .idle) }
                    }
                    StatusLine(
                        process: process, store: store,
                        details: [process.group, process.executable, process.uptime, process.memory])
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(process.isDev && !isStopping && !process.isSuspended ? .primary : .secondary)
            .accessibilityElement(children: .combine)
            if !isStopping && confirming != "pid:\(process.pid)" {
                IconButton(systemName: "arrow.up.right", label: "Abrir localhost:\(row.port.number) no navegador") {
                    store.openInBrowser(row.port.number)
                }
            }
            KillControl(process: process, store: store, confirming: $confirming)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 40)
        .help(process.argv.joined(separator: " "))
        .contextMenu {
            Button("Abrir no navegador") { store.openInBrowser(row.port.number) }
            RowMenu(process: process, store: store)
        }
    }
}

private struct ProcessRowView: View {
    let process: DevProcess
    let store: Store
    @Binding var confirming: String?

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(process.label).font(.system(size: 12)).lineLimit(1).layoutPriority(1)
                Text(" · ").font(.system(size: 11)).foregroundStyle(.secondary)
                if process.isSuspended {
                    Badge(text: "SUSPENSO", color: .idle)
                    Text(" · ").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                StatusLine(
                    process: process, store: store,
                    details: ["pid \(process.pid)", process.uptime, process.memory])
                Spacer(minLength: 0)
            }
            .foregroundStyle(store.stopping[process.pid] == nil && !process.isSuspended ? .primary : .secondary)
            .accessibilityElement(children: .combine)
            KillControl(process: process, store: store, confirming: $confirming)
        }
        .padding(.leading, 38)
        .padding(.trailing, 8)
        .frame(height: 30)
        .help(process.argv.joined(separator: " "))
        .contextMenu { RowMenu(process: process, store: store) }
    }
}

/// The metadata line, replaced by "encerrando…" while TERM is pending and by the warning once 5 s pass.
private struct StatusLine: View {
    let process: DevProcess
    let store: Store
    let details: [String]

    var body: some View {
        if let stopping = store.stopping[process.pid] {
            let isLate = stopping == .unresponsive
            Text(isLate ? "Não respondeu em 5 s" : "encerrando…")
                .font(.system(size: 11))
                .foregroundStyle(isLate ? Color.warningText : .secondary)
        } else {
            Text(details.joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// ✕ sends TERM right away on a dev row and asks first on a system row. While TERM is pending it becomes a spinner,
/// and "Forçar" (KILL) after 5 s without an exit.
private struct KillControl: View {
    let process: DevProcess
    let store: Store
    @Binding var confirming: String?

    var body: some View {
        let key = "pid:\(process.pid)"
        if let stopping = store.stopping[process.pid] {
            if stopping == .waiting {
                ProgressView().controlSize(.small).frame(width: 26, height: 26)
            } else {
                Button("Forçar") { store.terminate([process]) }
                    .buttonStyle(SmallButtonStyle(color: .danger, filled: false, strong: true))
            }
        } else if confirming == key {
            HStack(spacing: 6) {
                Button("Encerrar") {
                    confirming = nil
                    store.terminate([process])
                }
                .buttonStyle(SmallButtonStyle(color: .danger, filled: true))
                Button("Cancelar") { confirming = nil }.buttonStyle(SmallButtonStyle())
            }
        } else {
            HStack(spacing: 0) {
                if process.isDev { SuspendControl(process: process, store: store) }
                IconButton(systemName: "xmark", label: "Encerrar \(process.label), pid \(process.pid)") {
                    if process.isDev { store.terminate([process]) } else { confirming = key }
                }
            }
        }
    }
}

/// ⏸ sends SIGSTOP, ▶ sends SIGCONT. The port stays taken while suspended, so new connections wait.
private struct SuspendControl: View {
    let process: DevProcess
    let store: Store

    var body: some View {
        if process.isSuspended {
            IconButton(systemName: "play.fill", label: "Retomar \(process.label), pid \(process.pid)") {
                store.resume(process)
            }
        } else {
            IconButton(
                systemName: "pause.fill",
                label:
                    "Suspender \(process.label), pid \(process.pid). A porta continua ocupada e novas conexões ficam esperando."
            ) { store.suspend(process) }
        }
    }
}

private struct RowMenu: View {
    let process: DevProcess
    let store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let folder = process.projectPath ?? process.cwd {
            Button("Terminal na pasta") {
                store.openTerminal(title: process.project ?? process.group, folder: folder)
                store.showTerminal { openWindow(id: "terminal") }
            }
        }
        if process.cwd != nil {
            Button("Mostrar no Finder") { store.showInFinder(process) }
        }
        Button("Copiar comando") { store.copyCommand(process) }
        if process.isDev {
            Button("Reiniciar com log") { Task { await store.prepareRestart(process) } }
        }
    }
}

private struct ConfirmBand: View {
    let text: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            Button("Encerrar", action: confirm).buttonStyle(SmallButtonStyle(color: .danger, filled: true))
            Button("Cancelar", action: cancel).buttonStyle(SmallButtonStyle())
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(Color.danger.opacity(0.07), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.danger.opacity(0.22)))
    }
}

struct IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// DESIGN.md's small button: 24 pt, subtle border, or filled for the confirming action.
struct SmallButtonStyle: ButtonStyle {
    var color: Color = .primary
    var filled = false
    var strong = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: filled || strong ? .semibold : .regular))
            .foregroundStyle(filled ? Color.white : color)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(filled ? color : color.opacity(strong ? 0.08 : 0), in: .rect(cornerRadius: 6))
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(strong ? color.opacity(0.35) : Color.primary.opacity(0.14))
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.rect)
    }
}

struct Led: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
    }
}

struct Badge: View {
    let text: String
    let color: Color
    /// Darker than the LED in light mode, for contrast on the tinted background (DESIGN.md).
    var textColor: Color?

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.38)  // 0.04 em
            .foregroundStyle(textColor ?? color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.14), in: .rect(cornerRadius: 4))
    }
}

extension DevProcess {
    fileprivate var uptime: String { Format.uptime(Date.now.timeIntervalSince(startedAt)) }
    fileprivate var memory: String { Format.memory(memoryBytes) }
}

extension Store {
    /// Brings up the Terminal tab, with the sessions where the setting says: in the tab, or in the window, which
    /// `open` brings up while the tab shows the notice.
    func showTerminal(placement: TerminalSessions.Host = .preferred, open: () -> Void) {
        terminal.host = placement
        tab = .terminal
        if placement == .window { open() }
    }
}

/// "1 grupo", "7 grupos".
private func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}

#if DEBUG
    #Preview("Com processos") {
        PopoverView(store: .preview(Sample.all))
    }

    #Preview("Vazio") {
        PopoverView(store: .preview([]))
    }

    #Preview("Apps: lista longa") {
        var many: [ProcessNode] = []
        var cpu: [String: Double] = [:]
        for i in 0..<40 {
            let name: String = "App \(i)"
            let node = ProcessNode(
                pid: Int32(1000 + i), ppid: 1, uid: getuid(),
                path: "/Applications/" + name + ".app/Contents/MacOS/" + name,
                memoryBytes: Int64(i + 1) * 20_000_000, cpuSeconds: 0,
                startedAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(i)), isSuspended: false)
            many.append(node)
            cpu[node.key] = Double(40 - i)
        }
        return PopoverView(store: .preview([], nodes: many, cpu: cpu), startOn: .apps)
    }

    #Preview("Terminal: sem sessão") {
        PopoverView(store: .preview([]), startOn: .terminal)
    }

    #Preview("Terminal: aberto na janela") {
        let store = Store.preview([])
        store.terminal.host = .window
        return PopoverView(store: store, startOn: .terminal)
    }

    #Preview("Suspenso") {
        PopoverView(store: .preview([Sample.panel, Sample.suspended, Sample.exposed, Sample.worker]))
    }

    #Preview("Encerrando") {
        PopoverView(store: .preview(Sample.all, stopping: [Sample.site.pid: .waiting]))
    }

    #Preview("Não respondeu") {
        PopoverView(store: .preview(Sample.all, stopping: [Sample.site.pid: .unresponsive]))
    }

    #Preview("Confirmando") {
        // `confirming` is the popover's own @State, so the row is shown on its own.
        VStack(spacing: 0) {
            ProcessRowView(
                process: Sample.system, store: .preview(Sample.all), confirming: .constant("pid:\(Sample.system.pid)"))
        }
        .frame(width: 440)
    }
#endif
