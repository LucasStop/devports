#if DEBUG
    import Foundation

    /// Mock rows for `#Preview`; ports follow the local convention (painel 3000, site 3001).
    enum Sample {
        private static func ago(_ hours: Double) -> Date { Date.now.addingTimeInterval(-hours * 3600) }

        static let site = DevProcess(
            pid: 4101, ppid: 4100, executable: "node", argv: ["node", "next", "dev", "-p", "3001"], label: "next dev",
            cwd: "/Users/dev/GitHub/site", project: "site", group: "site",
            ports: [ListeningPort(number: 3001, isExposed: false)], memoryBytes: 412 * 1_048_576, startedAt: ago(2),
            isDev: true, projectPath: "/Users/dev/GitHub/site")

        static let panel = DevProcess(
            pid: 4102, ppid: 4100, executable: "node", argv: ["node", "vite", "--port", "3000"], label: "vite",
            cwd: "/Users/dev/GitHub/painel", project: "painel", group: "painel",
            ports: [ListeningPort(number: 3000, isExposed: false)], memoryBytes: 268 * 1_048_576, startedAt: ago(5),
            isDev: true, projectPath: "/Users/dev/GitHub/painel")

        /// Bound on all interfaces, so the row carries the REDE badge.
        static let exposed = DevProcess(
            pid: 4103, ppid: 1, executable: "python3", argv: ["python3", "-m", "http.server", "8000"],
            label: "http.server 8000", cwd: "/Users/dev/GitHub/docs", project: "docs", group: "docs",
            ports: [ListeningPort(number: 8000, isExposed: true)], memoryBytes: 18 * 1_048_576, startedAt: ago(0.3),
            isDev: true, projectPath: "/Users/dev/GitHub/docs")

        /// A dev process with no port: lands in "Processos dev", grouped by project.
        static let worker = DevProcess(
            pid: 4104, ppid: 4100, executable: "node", argv: ["node", "queue-worker.js"], label: "queue-worker",
            cwd: "/Users/dev/GitHub/painel", project: "painel", group: "painel", ports: [],
            memoryBytes: 96 * 1_048_576, startedAt: ago(5), isDev: true, projectPath: "/Users/dev/GitHub/painel")

        /// Hidden until "Mostrar sistema" is on; ends up in the footer count.
        static let system = DevProcess(
            pid: 612, ppid: 1, executable: "ControlCenter", argv: ["ControlCenter"], label: "ControlCenter",
            cwd: nil, project: nil, group: "Sistema", ports: [ListeningPort(number: 5000, isExposed: true)],
            memoryBytes: 64 * 1_048_576, startedAt: ago(40), isDev: false)

        /// `site` after SIGSTOP: gray LED, SUSPENSO badge, ▶ instead of ⏸.
        static var suspended: DevProcess {
            var process = site
            process.isSuspended = true
            return process
        }

        static let all = [site, panel, exposed, worker, system]
    }

    extension Sample {
        private static func node(
            _ pid: Int32, _ ppid: Int32, _ path: String, mem: Int64, stopped: Bool = false, uid: UInt32 = getuid()
        ) -> ProcessNode {
            ProcessNode(
                pid: pid, ppid: ppid, uid: uid, path: path, memoryBytes: mem * 1_048_576, cpuSeconds: 0,
                startedAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(pid)), isSuspended: stopped)
        }

        /// Chrome with two helpers, Slack stopped, Finder (protected), mds as root.
        static let appNodes: [ProcessNode] = [
            node(100, 1, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", mem: 900),
            node(
                101, 100,
                "/Applications/Google Chrome.app/Contents/Frameworks/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                mem: 412),
            node(
                102, 100,
                "/Applications/Google Chrome.app/Contents/Frameworks/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)",
                mem: 388),
            node(200, 1, "/Applications/Xcode.app/Contents/MacOS/Xcode", mem: 3400),
            node(300, 1, "/Applications/Slack.app/Contents/MacOS/Slack", mem: 812, stopped: true),
            node(400, 1, "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", mem: 210),
            node(500, 1, "/Applications/TextEdit.app/Contents/MacOS/TextEdit", mem: 64),
        ]

        static var appCPU: [String: Double] {
            let nodes = appNodes
            let values: [Int32: Double] = [100: 4.2, 101: 3.2, 102: 5.1, 200: 8.1, 300: 0, 400: 0.3, 500: 0]
            return Dictionary(uniqueKeysWithValues: nodes.map { ($0.key, values[$0.pid] ?? 0) })
        }
    }

    struct PreviewScanner: ProcessScanning {
        let processes: [DevProcess]
        func scan() -> [DevProcess] { processes }
    }
#endif
