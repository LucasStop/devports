import SwiftUI

/// The Ajustes panel inside the popover: where the Terminal opens and how big each tab is.
struct AjustesView: View {
    @Binding var sizes: PopoverSizes
    @Binding var placement: TerminalSessions.Host
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text("Ajustes").fontWeight(.semibold)
                    Text("· voltar").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 8, trailing: 14))
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                section("Terminal")
                row("Abrir em", detail: "Rodar script e Reiniciar usam esta opção") {
                    Picker("Abrir em", selection: $placement) {
                        Text("Popover").tag(TerminalSessions.Host.popover)
                        Text("Janela").tag(TerminalSessions.Host.window)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                section("Tamanho do popover")
                Toggle("Mesmo tamanho em todas as abas", isOn: $sizes.same).toggleStyle(.switch)
                if sizes.same {
                    SizeEditor(size: $sizes.all)
                } else {
                    SizeEditor(title: "Portas", size: $sizes.ports)
                    SizeEditor(title: "Apps", size: $sizes.apps)
                    if placement == .window {
                        Text("Terminal: sem efeito, ele abre em janela.")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary).opacity(0.7)
                    } else {
                        SizeEditor(title: "Terminal", size: $sizes.terminal)
                    }
                }
                HStack {
                    Text("Altura automática cresce com o conteúdo, até 660 pt.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Restaurar padrão") { sizes = PopoverSizes() }.buttonStyle(SmallButtonStyle())
                }
            }
            .font(.system(size: 12))
            .padding(14)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }

    private func row<Control: View>(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control)
        -> some View
    {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            control()
        }
    }
}

/// Width slider and an Automática/Fixa choice for the height.
private struct SizeEditor: View {
    var title: String?
    @Binding var size: PanelSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).fontWeight(.semibold) }
            HStack {
                Text("Largura").frame(width: 56, alignment: .leading)
                Slider(value: $size.width, in: PopoverSizes.widthRange, step: 10)
                Text("\(Int(size.width)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
            }
            HStack {
                Text("Altura").frame(width: 56, alignment: .leading)
                Picker("Altura", selection: automatic) {
                    Text("Automática").tag(true)
                    Text("Fixa").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                Spacer()
            }
            if let height = size.height {
                HStack {
                    Spacer().frame(width: 56)
                    Slider(
                        value: Binding(get: { height }, set: { size.height = $0 }), in: PopoverSizes.heightRange,
                        step: 10)
                    Text("\(Int(height)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    private var automatic: Binding<Bool> {
        Binding(
            get: { size.height == nil },
            set: { size.height = $0 ? nil : PopoverSizes.defaultFixedHeight })
    }
}

#if DEBUG
    #Preview("Ajustes") {
        @Previewable @State var sizes = PopoverSizes()
        @Previewable @State var placement = TerminalSessions.Host.popover
        AjustesView(sizes: $sizes, placement: $placement, back: {}).frame(width: 440)
    }
#endif
