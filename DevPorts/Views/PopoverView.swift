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
    @Environment(\.openWindow) private var openWindow

    /// DESIGN.md caps the popover at 660 pt; header, search field and footer take 127 of them.
    private static let maxListHeight: CGFloat = 533

    var body: some View {
        let overview = Overview(
            processes: store.processes, query: query, showSystem: showSystem,
            isPortTaken: ProcessScanner.isPortTaken)
        VStack(spacing: 0) {
            header
            searchField
            if overview.ports.isEmpty && overview.groups.isEmpty {
                emptyState(overview.searchedPort)
            } else {
                ScrollView {
                    list(overview).onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        listHeight = $0
                    }
                }
                // The window takes the smallest size the content allows, and a ScrollView shrinks to nothing, so it
                // gets the list's height as a floor.
                .frame(minHeight: min(listHeight, Self.maxListHeight))
            }
            if let banner = store.banner { errorBanner(banner) }
            if confirmingQuit { quitBand }
            if let pending = store.pendingRestart { restartBand(pending.process, command: pending.plan.command) }
            Divider()
            footer(hiddenCount: overview.hiddenCount)
        }
        .frame(width: 440)
        .onAppear { store.setPopoverOpen(true) }
        .onDisappear { store.setPopoverOpen(false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cable.connector")
            Text("DevPorts").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r")
            .help("Atualizar agora")
            .accessibilityLabel("Atualizar agora")
            Button {
                openWindow(id: "terminal")
            } label: {
                Image(systemName: "terminal").frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Abrir terminal")
            .accessibilityLabel("Abrir terminal")
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 8, trailing: 10))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar porta, processo ou projeto", text: $query).textFieldStyle(.plain)
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
                openWindow(id: "terminal")
            }
            if let scripts = ProjectScripts.read(root: folder) {
                Menu("Scripts") {
                    ForEach(scripts.names, id: \.self) { name in
                        Button("\(scripts.manager) run \(name)") {
                            store.openTerminal(
                                title: "\(group.name) · \(name)", folder: folder,
                                command: "\(scripts.manager) run \(name)")
                            openWindow(id: "terminal")
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
            ContentUnavailableView(
                "Nenhuma porta dev em uso", systemImage: "cable.connector",
                description: Text("Servidores que você subir aparecem aqui."))
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
                Task { if await store.confirmRestart() { openWindow(id: "terminal") } }
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

    private func footer(hiddenCount: Int) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: $showSystem) {
                HStack(spacing: 8) {
                    Text("Mostrar sistema")
                    Text(String(hiddenCount)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            Button("Terminal") { openWindow(id: "terminal") }
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
            Led(color: isStopping || !process.isDev ? .idle : row.port.isExposed ? .warning : .ok)
            HStack(spacing: 10) {
                Text(":" + String(row.port.number))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(process.label).font(.system(size: 13)).lineLimit(1)
                        if row.port.isExposed { Badge(text: "REDE", color: .warning) }
                        if !process.isDev { Badge(text: "SISTEMA", color: .idle) }
                    }
                    StatusLine(
                        process: process, store: store,
                        details: [process.group, process.executable, process.uptime, process.memory])
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(process.isDev && !isStopping ? .primary : .secondary)
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
                StatusLine(
                    process: process, store: store,
                    details: ["pid \(process.pid)", process.uptime, process.memory])
                Spacer(minLength: 0)
            }
            .foregroundStyle(store.stopping[process.pid] == nil ? .primary : .secondary)
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
                .foregroundStyle(isLate ? Color.warning : .secondary)
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
            IconButton(systemName: "xmark", label: "Encerrar \(process.label), pid \(process.pid)") {
                if process.isDev { store.terminate([process]) } else { confirming = key }
            }
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
                openWindow(id: "terminal")
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

private struct IconButton: View {
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
private struct SmallButtonStyle: ButtonStyle {
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

private struct Led: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.38)  // 0.04 em
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.14), in: .rect(cornerRadius: 4))
    }
}

extension Color {
    // ponytail: system stand-ins until slice 6 adds the DESIGN.md colorsets (Any/Dark) under these names.
    fileprivate static let ok = Color.green
    fileprivate static let warning = Color.orange
    fileprivate static let idle = Color.gray
    fileprivate static let danger = Color.red
}

extension DevProcess {
    fileprivate var uptime: String { Format.uptime(Date.now.timeIntervalSince(startedAt)) }
    fileprivate var memory: String { Format.memory(memoryBytes) }
}

/// "1 grupo", "7 grupos".
private func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}
