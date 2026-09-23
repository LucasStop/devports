import Darwin
import Foundation

/// Reads listening ports and dev processes from lsof, ps and sysctl. The parsers are pure so tests can feed them
/// captured output; `scan` is the only part that touches the system.
enum ProcessScanner {
    struct PSRow: Equatable, Sendable {
        let pid: Int32
        let ppid: Int32
        let memoryBytes: Int64
        let startedAt: Date
        let executable: String
    }

    // ponytail: this pattern is the knob for what counts as dev; widen it when a runtime is missing.
    private static let devPattern =
        #"^(node|bun|deno|python[0-9.]*|ruby|php|java|dart|go|postgres|redis-server|mysqld|mongod|ollama|com\.docker\.backend)$"#

    private static let projectMarkers = [
        ".git", "package.json", "pubspec.yaml", "pyproject.toml", "go.mod", "Cargo.toml", "Gemfile", "composer.json",
        "build.gradle", "pom.xml",
    ]

    static func scan(home: String = NSHomeDirectory()) -> [DevProcess] {
        let listening = parseListening(run("/usr/sbin/lsof", ["-nP", "-b", "-w", "-iTCP", "-sTCP:LISTEN", "-Fpn"]))
        let rows = parsePS(run("/bin/ps", ["-axww", "-o", "pid=,ppid=,rss=,lstart=,comm="]))
        let candidates = rows.filter { listening[$0.pid] != nil || isDevExecutable($0.executable) }
        guard !candidates.isEmpty else { return [] }

        let pids = candidates.map(\.pid)
        let pidList = pids.map(String.init).joined(separator: ",")
        let cwds = parseCwds(run("/usr/sbin/lsof", ["-b", "-w", "-a", "-d", "cwd", "-p", pidList, "-Fpn"]))
        let argvs = argvs(for: pids)

        return candidates.map { row in
            let cwd = cwds[row.pid]
            let projectPath = cwd.flatMap { projectRoot(cwd: $0, home: home) }
            let project = projectPath.map { ($0 as NSString).lastPathComponent }
            let argv = argvs[row.pid] ?? []
            return DevProcess(
                pid: row.pid,
                ppid: row.ppid,
                executable: row.executable,
                argv: argv,
                label: label(argv: argv, executable: row.executable),
                cwd: cwd,
                project: project,
                group: group(cwd: cwd, project: project, home: home),
                ports: listening[row.pid] ?? [],
                memoryBytes: row.memoryBytes,
                startedAt: row.startedAt,
                isDev: isDevExecutable(row.executable) || project != nil,
                projectPath: projectPath
            )
        }
    }

    /// Binds the port on loopback. lsof can't read other users' processes, but the kernel refuses the bind while one
    /// of them listens there (root's nginx on :80). netstat would list them too, yet run from an app it shows no inet
    /// sockets at all. SO_REUSEADDR keeps TIME_WAIT leftovers of a stopped server from counting as taken.
    static func isPortTaken(_ port: Int) -> Bool {
        var v4 = sockaddr_in()
        v4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        v4.sin_family = sa_family_t(AF_INET)
        v4.sin_port = in_port_t(port).bigEndian
        v4.sin_addr.s_addr = in_addr_t(0x7f00_0001).bigEndian
        var v6 = sockaddr_in6()
        v6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        v6.sin6_family = sa_family_t(AF_INET6)
        v6.sin6_port = in_port_t(port).bigEndian
        v6.sin6_addr = in6addr_loopback
        return bindFails(v4, family: AF_INET) || bindFails(v6, family: AF_INET6)
    }

    // MARK: - Parsers

    /// `lsof -Fpn` output; a port bound on both IPv4 and IPv6 becomes one entry, exposed if either side is.
    static func parseListening(_ output: String) -> [Int32: [ListeningPort]] {
        var exposedByPort: [Int32: [Int: Bool]] = [:]
        for (pid, name) in records(output) {
            guard let colon = name.lastIndex(of: ":"), let port = Int(name[name.index(after: colon)...]) else {
                continue
            }
            let current = exposedByPort[pid]?[port] ?? false
            exposedByPort[pid, default: [:]][port] = current || isExposed(host: String(name[..<colon]))
        }
        return exposedByPort.mapValues { ports in
            ports.map { ListeningPort(number: $0.key, isExposed: $0.value) }.sorted { $0.number < $1.number }
        }
    }

    static func parseCwds(_ output: String) -> [Int32: String] {
        Dictionary(records(output).map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// `ps -o pid=,ppid=,rss=,lstart=,comm=` under `LC_ALL=C`. `lstart` spans five words and `comm` may contain
    /// spaces, so the line is cut after the eighth word instead of being split on every space.
    static func parsePS(_ output: String, timeZone: TimeZone = .current) -> [PSRow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return output.split(separator: "\n").compactMap { line in
            let words = line.split(separator: " ", maxSplits: 8)
            guard words.count == 9,
                let pid = Int32(words[0]),
                let ppid = Int32(words[1]),
                let rss = Int64(words[2]),
                let startedAt = startDate(words[4...7], calendar: calendar)
            else { return nil }
            let path = words[8].trimmingCharacters(in: .whitespaces)
            return PSRow(
                pid: pid,
                ppid: ppid,
                memoryBytes: rss * 1024,
                startedAt: startedAt,
                executable: (path as NSString).lastPathComponent
            )
        }
    }

    /// `KERN_PROCARGS2` layout: argc as Int32, the exec path, NUL padding, argc NUL-terminated argv strings, then
    /// the environment, which is never read.
    static func parseProcArgs(_ bytes: [UInt8]) -> [String]? {
        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        var argv: [String] = []
        while argv.count < argc {
            guard let end = bytes[index...].firstIndex(of: 0) else { return nil }
            argv.append(String(decoding: bytes[index..<end], as: UTF8.self))
            index = end + 1
        }
        return argv
    }

    // MARK: - Classification

    static func isDevExecutable(_ name: String) -> Bool {
        name.range(of: devPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A readable name from argv, tried in order: a script or jar path, `python -m module`, a subcommand right after
    /// the executable, node's process.title. The next plain argument is appended (`expo run:ios`, `http.server 8000`).
    static func label(argv: [String], executable: String) -> String {
        let arguments = argv.dropFirst().filter { !$0.isEmpty }
        if let index = arguments.firstIndex(where: isPath) {
            return withNextPlain(shortName(arguments[index]), after: index, in: arguments)
        }
        if arguments.first == "-m", arguments.count > 1 {
            return withNextPlain(arguments[1], after: 1, in: arguments)
        }
        if let first = arguments.first, !first.hasPrefix("-") {
            return withNextPlain(first, after: 0, in: arguments)
        }
        // node overwrites argv with process.title ("npm run dev") and blanks the rest of it.
        if let title = argv.first, title.contains(" "), !title.hasPrefix("/") { return title }
        return executable
    }

    /// Nearest folder with a project marker. Only searched inside home, and never under hidden folders or
    /// ~/Library, where tool caches (npx, gradle, VS Code extensions) carry package.json files of their own.
    static func projectName(cwd: String, home: String) -> String? {
        projectRoot(cwd: cwd, home: home).map { ($0 as NSString).lastPathComponent }
    }

    static func projectRoot(cwd: String, home: String) -> String? {
        guard cwd.hasPrefix(home + "/") else { return nil }
        let components = cwd.dropFirst(home.count + 1).split(separator: "/")
        guard components.first != "Library", !components.contains(where: { $0.hasPrefix(".") }) else { return nil }

        var folder = URL(fileURLWithPath: cwd)
        while folder.path.count > home.count {
            let hasMarker = projectMarkers.contains {
                FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
            }
            if hasMarker { return folder.path }
            folder.deleteLastPathComponent()
        }
        return nil
    }

    /// Outside a project, tool caches (hidden folders, ~/Library) group by their top folder so all gradle daemons
    /// land together; any other folder groups by its own name, since that is where the process was started.
    static func group(cwd: String?, project: String?, home: String) -> String {
        if let project { return project }
        guard let cwd, cwd == home || cwd.hasPrefix(home + "/") else { return "Sistema" }
        let components = cwd.dropFirst(home.count).split(separator: "/")
        guard let first = components.first, let last = components.last else { return "~" }
        let isToolCache = first == "Library" || components.contains(where: { $0.hasPrefix(".") })
        return isToolCache ? "~/\(first)" : String(last)
    }

    // MARK: - Helpers

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// `Sep 21 12:27:45 2026` (lstart minus the weekday). Parsed by hand because DateFormatter cost ~40 µs a line
    /// and ps lists every process on the machine.
    private static func startDate(_ words: ArraySlice<Substring>, calendar: Calendar) -> Date? {
        let words = Array(words)
        let time = words[2].split(separator: ":").compactMap { Int($0) }
        guard let month = months.firstIndex(of: String(words[0])), let day = Int(words[1]), time.count == 3,
            let year = Int(words[3])
        else { return nil }
        let components = DateComponents(
            year: year, month: month + 1, day: day, hour: time[0], minute: time[1], second: time[2])
        return calendar.date(from: components)
    }

    /// Pairs every `n` field with the `p` field above it; the `f` lines lsof always prints are skipped.
    private static func records(_ output: String) -> [(pid: Int32, name: String)] {
        var pid: Int32?
        var result: [(pid: Int32, name: String)] = []
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                pid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid {
                result.append((pid, String(line.dropFirst())))
            }
        }
        return result
    }

    /// Anything not bound to loopback (a wildcard or a LAN address) is reachable from other machines.
    private static func isExposed(host: String) -> Bool {
        !(host.hasPrefix("127.") || host == "[::1]" || host.hasPrefix("[::ffff:127."))
    }

    private static let entryFiles: Set<Substring> = ["index.js", "index.mjs", "index.cjs", "main.js", "cli.js"]
    private static let buildFolders: Set<Substring> = ["build", "dist", "out", "lib", "src", "bin"]

    /// Script and jar paths; a flag value such as `jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED` is not one.
    private static func isPath(_ argument: String) -> Bool {
        argument.contains("/") && !argument.contains("=") && !argument.hasPrefix("-")
    }

    private static func shortName(_ path: String) -> String {
        // A java classpath lists several jars joined by ':'; the first one names the program.
        let path = path.split(separator: ":").first.map(String.init) ?? path
        if let range = path.range(of: "/node_modules/", options: .backwards) {
            let parts = path[range.upperBound...].split(separator: "/")
            if parts.count > 1, parts[0] == ".bin" || parts[0].hasPrefix("@") {
                return parts[0] == ".bin" ? String(parts[1]) : "\(parts[0])/\(parts[1])"
            }
            if let package = parts.first { return String(package) }
        }
        let components = path.split(separator: "/")
        guard let name = components.last else { return path }
        // `build/index.js` says nothing; the folder that holds the build is the package.
        if entryFiles.contains(name), let folder = components.dropLast().last(where: { !buildFolders.contains($0) }) {
            return String(folder)
        }
        return name.hasSuffix(".jar") ? String(name.dropLast(4)) : String(name)
    }

    private static func withNextPlain(_ name: String, after index: Int, in arguments: [String]) -> String {
        guard index + 1 < arguments.count, isPlain(arguments[index + 1]) else { return name }
        return "\(name) \(arguments[index + 1])"
    }

    /// Subcommands and values such as `run:ios`, `dev` or `8000`; dotted names (java main classes) and paths are not.
    private static func isPlain(_ argument: String) -> Bool {
        argument.range(of: #"^[A-Za-z0-9:_@=+][A-Za-z0-9:_@=+-]*$"#, options: .regularExpression) != nil
    }

    /// One KERN_ARGMAX buffer is reused for every pid; allocating it per process would churn megabytes per refresh.
    private static func argvs(for pids: [Int32]) -> [Int32: [String]] {
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var argmaxName: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argmaxName, 2, &argmax, &size, nil, 0) == 0, argmax > 0 else { return [:] }

        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        var result: [Int32: [String]] = [:]
        for pid in pids {
            var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            var length = buffer.count
            guard sysctl(&name, 3, &buffer, &length, nil, 0) == 0 else { continue }
            result[pid] = parseProcArgs(Array(buffer[..<length]))
        }
        return result
    }

    private static func bindFails<Address>(_ address: Address, family: Int32) -> Bool {
        let socket = Darwin.socket(family, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var reuse: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = address
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<Address>.size))
            }
        }
        return result != 0 && errno == EADDRINUSE
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // Not waitUntilExit(): it polls the run loop and added ~65 ms to every command in a refresh.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return "" }
        // Read before waiting: output larger than the pipe buffer would otherwise block the child forever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        return String(decoding: data, as: UTF8.self)
    }
}
