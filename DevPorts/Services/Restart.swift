import Foundation

/// Rebuilds the command that started a server so the app can stop it and start it again in a Terminal tab.
enum Restart {
    struct Target: Sendable {
        let pid: Int32
        let startedAt: Date
    }

    /// The root command, where it ran, and every process to stop before running it again.
    struct Plan: Sendable {
        let command: String
        let folder: String
        let targets: [Target]
    }

    struct Proc: Equatable, Sendable {
        let pid: Int32
        let ppid: Int32
        let executable: String
        let argv: [String]
    }

    /// Climbs while the parent is part of the same launch: a dev runtime (npm runs as node) or `sh -c`. Stops at an
    /// interactive shell, launchd or an app, which started the command and are not part of it.
    static func root(of pid: Int32, in table: [Proc]) -> Int32 {
        let byPid = Dictionary(table.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var root = pid
        while let current = byPid[root], current.ppid > 1, let parent = byPid[current.ppid],
            isLaunchStep(parent)
        {
            root = parent.pid
        }
        return root
    }

    static func descendants(of pid: Int32, parents: [Int32: Int32]) -> [Int32] {
        let children = Dictionary(grouping: parents.keys, by: { parents[$0]! })
        var result: [Int32] = []
        var queue = [pid]
        while let next = queue.popLast() {
            let found = children[next] ?? []
            result += found
            queue += found
        }
        return result.sorted()
    }

    /// A shell line for argv. When node rewrote argv into one title string ("npm run dev"), that string is typed as
    /// is only if it is plain words; anything else is quoted rather than run.
    static func command(argv: [String]) -> String {
        // The title rewrite also blanks the arguments after it.
        let argv = argv.filter { !$0.isEmpty }
        if argv.count == 1, argv[0].contains(" ") {
            return argv[0].range(of: #"^[A-Za-z0-9 ._:/@=+-]+$"#, options: .regularExpression) != nil
                ? argv[0] : quote(argv[0])
        }
        return argv.map(quote).joined(separator: " ")
    }

    private static func quote(_ argument: String) -> String {
        if argument.range(of: #"^[A-Za-z0-9._:/@=+-]+$"#, options: .regularExpression) != nil { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// node sets `process.title`, which on macOS also renames the process: npm shows up as "npm run dev".
    private static func isLaunchStep(_ proc: Proc) -> Bool {
        let name = String(proc.executable.split(separator: " ").first ?? "")
        if ProcessScanner.isDevExecutable(name) || ["npm", "npx", "pnpm", "yarn"].contains(name) { return true }
        return ["sh", "bash", "zsh"].contains(name) && proc.argv.dropFirst().first == "-c"
    }
}
