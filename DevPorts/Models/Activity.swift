import Foundation

/// What the Apps tab lists: processes grouped by app, with CPU and the pause rules. Pure, so tests feed it nodes.
enum Activity {
    enum Kind: Equatable {
        case normal
        /// Pausing it would freeze the desktop or the app itself: no button.
        case protected
        /// Another user's: signals would fail with EPERM: no button.
        case other
    }

    enum Sort: String, CaseIterable {
        case cpu, memory, name
    }

    struct App: Identifiable, Equatable {
        let id: String
        let name: String
        /// Oldest first, so the app itself comes before its helpers.
        let members: [ProcessNode]
        /// nil on the first scan, when there is no earlier reading to compare with.
        let cpu: Double?
        let kind: Kind
        /// Its root belongs to another user: the same test as the "Mostrar sistema" filter, for the SISTEMA badge.
        let isSystem: Bool

        var memoryBytes: Int64 { members.reduce(0) { $0 + $1.memoryBytes } }
        var isSuspended: Bool { members.contains { $0.isSuspended } }
    }

    /// Names whose pause freezes the desktop; the app's own process and its ancestors are added at runtime.
    static let protectedNames: Set<String> = [
        "launchd", "kernel_task", "WindowServer", "loginwindow", "Dock", "Finder", "SystemUIServer",
    ]

    /// CPU % per process: CPU seconds gained since `previous` over the wall-clock seconds between the scans.
    static func cpuPercent(now: [ProcessNode], previous: [String: Double], interval: Double) -> [String: Double] {
        guard interval > 0 else { return [:] }
        return Dictionary(
            now.map { node in
                let gained = previous[node.key].map { max(0, node.cpuSeconds - $0) } ?? 0
                return (node.key, gained / interval * 100)
            }, uniquingKeysWith: { first, _ in first })
    }

    /// `/Applications/Google Chrome.app` out of a path inside the bundle.
    static func bundlePath(_ path: String) -> String? {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            parts.append(part)
            if part.hasSuffix(".app") { return "/" + parts.joined(separator: "/") }
        }
        return nil
    }

    static func apps(
        nodes: [ProcessNode], cpu: [String: Double]?, me: UInt32, ownPid: Int32, showSystem: Bool,
        query: String = "", sort: Sort = .cpu
    ) -> [App] {
        let byPid = Dictionary(nodes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        func root(of node: ProcessNode) -> ProcessNode {
            var current = node
            var steps = 0
            while current.ppid > 1, let parent = byPid[current.ppid], parent.pid != current.pid, steps < 64 {
                current = parent
                steps += 1
            }
            return current
        }
        var own: Set<Int32> = []
        var climbing = byPid[ownPid]
        while let node = climbing, own.insert(node.pid).inserted { climbing = byPid[node.ppid] }

        let query = query.trimmingCharacters(in: .whitespaces)
        let number = Int32(query)
        let groups = Dictionary(grouping: nodes) { node -> String in
            let top = root(of: node)
            return bundlePath(top.path) ?? "pid:" + top.key
        }
        let apps = groups.compactMap { key, members -> App? in
            let members = members.sorted { ($0.startedAt, $0.pid) < ($1.startedAt, $1.pid) }
            let top = root(of: members[0])
            guard showSystem || top.uid == me else { return nil }
            let isProtected = members.contains {
                $0.pid == 1 || own.contains($0.pid) || protectedNames.contains($0.executable)
            }
            let kind: Kind = isProtected ? .protected : members.contains { $0.uid != me } ? .other : .normal
            let name =
                bundlePath(top.path).map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
                ?? top.executable
            if !query.isEmpty {
                let hit =
                    name.localizedStandardContains(query)
                    || (number.map { n in members.contains { $0.pid == n } } ?? false)
                guard hit else { return nil }
            }
            return App(
                id: key, name: name, members: members,
                cpu: cpu.map { map in members.reduce(0) { $0 + (map[$1.key] ?? 0) } },
                kind: kind, isSystem: top.uid != me)
        }
        switch sort {
        case .cpu:
            return apps.sorted { ($0.cpu ?? 0, $0.memoryBytes, $1.name) > ($1.cpu ?? 0, $1.memoryBytes, $0.name) }
        case .memory: return apps.sorted { ($0.memoryBytes, $1.name) > ($1.memoryBytes, $0.name) }
        case .name: return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
