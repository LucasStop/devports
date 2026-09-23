import SwiftUI

@main
struct DevPortsApp: App {
    var body: some Scene {
        MenuBarExtra("DevPorts", systemImage: "cable.connector") {
            Text("DevPorts")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
