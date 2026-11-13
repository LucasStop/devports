import Foundation

/// One row of `ps` for the Apps tab: every process of the machine, not just dev ones.
struct ProcessNode: Equatable, Sendable {
    let pid: Int32
    let ppid: Int32
    let uid: UInt32
    let path: String
    let memoryBytes: Int64
    /// Accumulated CPU time (`ps time`); two scans turn it into a percentage.
    let cpuSeconds: Double
    let startedAt: Date
    let isSuspended: Bool

    var executable: String { (path as NSString).lastPathComponent }
    /// pid plus start second, so a recycled pid is never taken for the old process.
    var key: String { "\(pid)@\(Int(startedAt.timeIntervalSince1970))" }
}

protocol ActivityScanning: Sendable {
    func scan() -> [ProcessNode]
}

struct SystemActivityScanner: ActivityScanning {
    func scan() -> [ProcessNode] { ActivityScanner.scan() }
}

enum ActivityScanner {
    static func scan() -> [ProcessNode] {
        parse(ProcessScanner.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,uid=,rss=,stat=,time=,lstart=,comm="]))
    }

    /// `ps -o pid=,ppid=,uid=,rss=,stat=,time=,lstart=,comm=` under `LC_ALL=C`; same cut-after-the-lstart trick as
    /// `ProcessScanner.parsePS`.
    static func parse(_ output: String, timeZone: TimeZone = .current) -> [ProcessNode] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return output.split(separator: "\n").compactMap { line in
            let words = line.split(separator: " ", maxSplits: 11)
            guard words.count == 12,
                let pid = Int32(words[0]),
                let ppid = Int32(words[1]),
                let uid = UInt32(words[2]),
                let rss = Int64(words[3]),
                let cpu = cpuSeconds(words[5]),
                let startedAt = ProcessScanner.startDate(words[7...10], calendar: calendar)
            else { return nil }
            return ProcessNode(
                pid: pid, ppid: ppid, uid: uid, path: words[11].trimmingCharacters(in: .whitespaces),
                memoryBytes: rss * 1024, cpuSeconds: cpu, startedAt: startedAt, isSuspended: words[4].contains("T"))
        }
    }

    /// `0:01.23`, `12:34.56`, `1:02:03` or `2-03:04:05` to seconds.
    static func cpuSeconds(_ text: Substring) -> Double? {
        var days = 0.0
        var rest = text
        if let dash = text.firstIndex(of: "-") {
            guard let d = Double(text[..<dash]) else { return nil }
            days = d
            rest = text[text.index(after: dash)...]
        }
        let parts = rest.split(separator: ":").map { Double($0) }
        guard (2...3).contains(parts.count), !parts.contains(where: { $0 == nil }) else { return nil }
        return days * 86400 + parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }
}
