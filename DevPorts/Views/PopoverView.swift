import SwiftUI

/// The menu bar popover: dev ports first, then dev processes without a port, grouped by project (DESIGN.md).
struct PopoverView: View {
    let store: Store
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @AppStorage("showSystem") private var showSystem = false
    @State private var listHeight: CGFloat = 0

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
                ForEach(overview.ports) { PortRowView(row: $0) }
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
        return VStack(spacing: 0) {
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
                .padding(.horizontal, 14)
                .frame(height: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Aberto" : "Fechado")
            if isExpanded {
                ForEach(group.processes) { ProcessRowView(process: $0) }
            }
        }
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
            Button("Sair") { NSApplication.shared.terminate(nil) }
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

    var body: some View {
        let process = row.process
        HStack(spacing: 10) {
            Led(color: !process.isDev ? .idle : row.port.isExposed ? .warning : .ok)
            Text(":" + String(row.port.number))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(process.label).font(.system(size: 13)).lineLimit(1)
                    if row.port.isExposed { Badge(text: "REDE", color: .warning) }
                    if !process.isDev { Badge(text: "SISTEMA", color: .idle) }
                }
                Text([process.group, process.executable, process.uptime, process.memory].joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(process.isDev ? .primary : .secondary)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 40)
        .help(process.argv.joined(separator: " "))
        .accessibilityElement(children: .combine)
    }
}

private struct ProcessRowView: View {
    let process: DevProcess

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(process.label).font(.system(size: 12)).lineLimit(1).layoutPriority(1)
            Text(" · pid \(String(process.pid)) · \(process.uptime) · \(process.memory)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 38)
        .padding(.trailing, 8)
        .frame(height: 30)
        .help(process.argv.joined(separator: " "))
        .accessibilityElement(children: .combine)
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
}

extension DevProcess {
    fileprivate var uptime: String { Format.uptime(Date.now.timeIntervalSince(startedAt)) }
    fileprivate var memory: String { Format.memory(memoryBytes) }
}

/// "1 grupo", "7 grupos".
private func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}
