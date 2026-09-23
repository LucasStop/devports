import SwiftUI

@main
struct DevPortsApp: App {
    @State private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            HStack {
                Image(systemName: "cable.connector").accessibilityLabel("DevPorts")
                // The count hides at zero, leaving only the glyph (DESIGN.md).
                if store.devPortCount > 0 { Text(String(store.devPortCount)) }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Terminal", id: "terminal") {
            TerminalWindow(store: store, terminal: store.terminal)
        }
        .defaultSize(width: 860, height: 520)
    }
}
