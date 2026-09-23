import Foundation

/// What the popover lists for one scan, a search query and the "Mostrar sistema" toggle. Pure, so tests feed it
/// processes directly.
struct Overview {
    struct PortRow: Identifiable, Equatable {
        let port: ListeningPort
        let process: DevProcess
        var id: String { "\(process.pid):\(port.number)" }
    }

    struct ProcessGroup: Identifiable, Equatable {
        let name: String
        let processes: [DevProcess]
        var memoryBytes: Int64 { processes.reduce(0) { $0 + $1.memoryBytes } }
        var id: String { name }
    }

    /// A searched port no row matched: free, or held by another user's process, which lsof can't see.
    struct SearchedPort: Equatable {
        let number: Int
        let isFree: Bool
    }

    let ports: [PortRow]
    /// Dev processes with no port on screen, by project or folder.
    let groups: [ProcessGroup]
    /// Rows the toggle reveals: ports of non-dev processes and dynamic ports.
    let hiddenCount: Int
    let searchedPort: SearchedPort?

    /// A query searches hidden rows too, since asking for :5000 must find ControlCenter with the toggle off. A number
    /// matches a port or a pid exactly; text matches the label, the executable or the group.
    init(
        processes: [DevProcess], query: String = "", showSystem: Bool = false,
        isPortTaken: (Int) -> Bool = { _ in false }
    ) {
        let query = String(query.trimmingCharacters(in: .whitespaces).trimmingPrefix(":"))
        let number = Int(query)
        let rows = processes.flatMap { process in process.ports.map { PortRow(port: $0, process: process) } }
        let isHidden = { (row: PortRow) in !row.process.isDev || row.port.isDynamic }
        let shown = showSystem || !query.isEmpty ? rows : rows.filter { !isHidden($0) }
        let pidsWithRows = Set(shown.map(\.process.pid))

        func matches(_ process: DevProcess) -> Bool {
            if let number { return process.pid == number }
            return [process.label, process.executable, process.group].contains { $0.localizedStandardContains(query) }
        }

        let ports =
            shown
            .filter { query.isEmpty || $0.port.number == number || matches($0.process) }
            .sorted { ($0.port.number, $0.process.pid) < ($1.port.number, $1.process.pid) }
        let groups = Dictionary(grouping: processes.filter { $0.isDev && !pidsWithRows.contains($0.pid) }, by: \.group)
            .compactMap { name, members -> ProcessGroup? in
                let keepsAll = query.isEmpty || (number == nil && name.localizedStandardContains(query))
                let kept = (keepsAll ? members : members.filter(matches)).sorted {
                    $0.memoryBytes != $1.memoryBytes ? $0.memoryBytes > $1.memoryBytes : $0.pid < $1.pid
                }
                return kept.isEmpty ? nil : ProcessGroup(name: name, processes: kept)
            }
            .sorted { $0.memoryBytes != $1.memoryBytes ? $0.memoryBytes > $1.memoryBytes : $0.name < $1.name }

        self.ports = ports
        self.groups = groups
        hiddenCount = rows.filter(isHidden).count
        if let number, (1...65535).contains(number), ports.isEmpty, groups.isEmpty {
            searchedPort = SearchedPort(number: number, isFree: !isPortTaken(number))
        } else {
            searchedPort = nil
        }
    }
}
