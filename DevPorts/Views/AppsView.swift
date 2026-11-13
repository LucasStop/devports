import SwiftUI

/// The Apps tab: every process grouped by app, with CPU and memory, and one button that pauses the app together
/// with its helpers (DESIGN.md, A01 to A10).
struct AppsView: View {
    let store: Store
    let query: String
    let showSystem: Bool
    var fills = false
    @AppStorage("appsSort") private var sortRaw = Activity.Sort.cpu.rawValue
    @State private var expanded: Set<String> = []
    @State private var confirming: String?

    /// The ports cap (531) minus this view's own two header rows (44): DESIGN.md limits the popover to 660 pt.
    private static let maxHeight: CGFloat = 487
    private var sort: Activity.Sort { Activity.Sort(rawValue: sortRaw) ?? .cpu }

    var body: some View {
        let apps = Activity.apps(
            nodes: store.activityNodes, cpu: store.cpu, me: getuid(), ownPid: getpid(), showSystem: showSystem,
            query: query, sort: sort)
        if apps.isEmpty {
            empty
        } else {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Apps").fontWeight(.semibold)
                    Text("\(apps.count) em uso")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(EdgeInsets(top: 6, leading: 14, bottom: 4, trailing: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                columnHeader
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(apps) { row($0) }
                    }
                    .padding(.bottom, 6)
                }
                .frame(height: fills ? nil : min(height(of: apps), Self.maxHeight))
                .frame(maxHeight: fills ? .infinity : nil)
            }
        }
    }

    private func height(of apps: [Activity.App]) -> CGFloat {
        apps.reduce(6) {
            $0 + 40 + (expanded.contains($1.id) ? CGFloat($1.members.count) * 28 : 0) + (confirming == $1.id ? 56 : 0)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Nome").frame(maxWidth: .infinity, alignment: .leading)
            sortButton("CPU", .cpu).frame(width: 52, alignment: .trailing)
            sortButton("Memória", .memory).frame(width: 64, alignment: .trailing)
            Color.clear.frame(width: 26, height: 1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(EdgeInsets(top: 2, leading: 14, bottom: 4, trailing: 8))
    }

    private func sortButton(_ title: String, _ value: Activity.Sort) -> some View {
        Button(sort == value ? "\(title) ▾" : title) { sortRaw = value.rawValue }
            .buttonStyle(.plain)
            .fontWeight(sort == value ? .semibold : .regular)
            .foregroundStyle(sort == value ? Color.primary : .secondary)
            .accessibilityLabel("Ordenar por \(title)")
    }

    private func row(_ app: Activity.App) -> some View {
        let isOpen = expanded.contains(app.id)
        let locked = app.kind != .normal
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    expanded.formSymmetricDifference([app.id])
                } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                        .opacity(app.members.count > 1 ? 1 : 0)
                }
                .buttonStyle(.plain)
                .disabled(app.members.count < 2)
                .accessibilityLabel(isOpen ? "Recolher \(app.name)" : "Expandir \(app.name)")
                Text(String(app.name.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 6))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(app.name).font(.system(size: 13)).lineLimit(1)
                        if app.isSystem { Badge(text: "SISTEMA", color: .idle) }
                        if app.isSuspended { Badge(text: "SUSPENSO", color: .idle) }
                    }
                    Text(app.members.count == 1 ? "1 processo" : "\(app.members.count) processos")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(app.isSuspended || locked ? .secondary : .primary)
                Spacer(minLength: 0)
                Text(cpu(app.isSuspended ? 0 : app.cpu)).frame(width: 52, alignment: .trailing)
                Text(Format.memory(app.memoryBytes)).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                control(app)
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 40)
            if confirming == app.id { confirmBand(app) }
            if isOpen {
                ForEach(app.members, id: \.key) { child($0) }
            }
        }
    }

    private func child(_ node: ProcessNode) -> some View {
        HStack(spacing: 8) {
            Text(node.executable).font(.system(size: 12, design: .default)).lineLimit(1)
            Spacer(minLength: 0)
            Text("pid \(node.pid)").font(.system(size: 11, design: .default)).foregroundStyle(.secondary)
            Text(cpu(node.isSuspended ? 0 : store.cpu?[node.key])).frame(width: 52, alignment: .trailing)
            Text(Format.memory(node.memoryBytes)).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            Color.clear.frame(width: 26, height: 1)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.leading, 44)
        .padding(.trailing, 8)
        .frame(height: 28)
    }

    @ViewBuilder
    private func control(_ app: Activity.App) -> some View {
        if confirming == app.id {
            Color.clear.frame(width: 26, height: 26)
        } else if app.kind != .normal {
            IconButton(
                systemName: "lock",
                label: app.kind == .protected
                    ? "\(app.name) é protegido: pausá-lo congela a área de trabalho e o sistema."
                    : "\(app.name) pertence a outro usuário."
            ) {}
            .disabled(true)
            .opacity(0.45)
        } else if app.isSuspended {
            IconButton(systemName: "play.fill", label: "Retomar \(app.name)") { store.resumeApp(app) }
        } else {
            IconButton(
                systemName: "pause.fill",
                label: "Pausar \(app.name). Ele congela, com os \(app.members.count) processos, até você retomar."
            ) {
                if app.members.count > 1 { confirming = app.id } else { store.suspendApp(app) }
            }
        }
    }

    private func confirmBand(_ app: Activity.App) -> some View {
        HStack(spacing: 8) {
            Text("Pausar \(app.name) e \(app.members.count - 1) processos auxiliares? Ele congela até você retomar.")
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Pausar") {
                confirming = nil
                store.suspendApp(app)
            }
            .buttonStyle(SmallButtonStyle(color: .danger, filled: true))
            Button("Cancelar") { confirming = nil }.buttonStyle(SmallButtonStyle())
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(Color.danger.opacity(0.07), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.danger.opacity(0.22)))
        .padding(EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 12))
    }

    @ViewBuilder
    private var empty: some View {
        if store.activityNodes.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ContentUnavailableView(
                "Nada encontrado", systemImage: "magnifyingglass",
                description: Text("Nenhum app ou processo com “\(query)”."))
        }
    }

    /// pt-BR decimal comma; "—" while there is only one reading.
    private func cpu(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR"))) + " %"
    }
}

#if DEBUG
    #Preview("Apps") {
        AppsView(store: .preview([], nodes: Sample.appNodes, cpu: Sample.appCPU), query: "", showSystem: false)
            .frame(width: 440)
    }

    #Preview("Apps: primeira leitura") {
        AppsView(store: .preview([], nodes: Sample.appNodes), query: "", showSystem: false).frame(width: 440)
    }
#endif
