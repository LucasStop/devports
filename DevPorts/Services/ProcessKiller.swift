import Darwin
import Foundation

/// Sends TERM, then KILL on a second request. Both calls are parameters so tests never signal a real process.
final class ProcessKiller {
    enum Outcome: Equatable {
        case sent(Int32)
        case gone
        case notPermitted
        case pidReused
    }

    private let send: (pid_t, Int32) -> Int32
    private let startTime: (pid_t) -> Date?
    /// Keyed by pid and start second, so a recycled pid starts over at TERM.
    private var terminated: Set<String> = []

    init(
        send: @escaping (pid_t, Int32) -> Int32 = { kill($0, $1) == 0 ? 0 : errno },
        startTime: @escaping (pid_t) -> Date? = ProcessKiller.startTime
    ) {
        self.send = send
        self.startTime = startTime
    }

    /// Re-reads the start time first: a pid freed after the scan may already belong to another process.
    func terminate(_ process: DevProcess) -> Outcome {
        terminate(pid: process.pid, startedAt: process.startedAt)
    }

    func terminate(pid: pid_t, startedAt: Date) -> Outcome {
        guard let current = startTime(pid) else { return .gone }
        let key = "\(pid)@\(Int(startedAt.timeIntervalSince1970))"
        guard Int(current.timeIntervalSince1970) == Int(startedAt.timeIntervalSince1970) else { return .pidReused }
        let signal = terminated.contains(key) ? SIGKILL : SIGTERM
        switch send(pid, signal) {
        case 0:
            terminated.insert(key)
            return .sent(signal)
        case ESRCH: return .gone
        default: return .notPermitted
        }
    }

    static func startTime(_ pid: pid_t) -> Date? {
        guard let start = info(pid)?.kp_proc.p_un.__p_starttime else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    /// The job a process belongs to: a shell puts each command line, with everything it spawns, in one group.
    static func processGroup(_ pid: pid_t) -> pid_t? { info(pid)?.kp_eproc.e_pgid }

    /// KILLs the whole job, after checking that its leader is still the process that started at `startedAt`.
    static func killGroup(_ leader: pid_t, startedAt: Date) -> Outcome {
        guard let current = startTime(leader) else { return .gone }
        guard Int(current.timeIntervalSince1970) == Int(startedAt.timeIntervalSince1970) else { return .pidReused }
        if kill(-leader, SIGKILL) == 0 { return .sent(SIGKILL) }
        return errno == ESRCH ? .gone : .notPermitted
    }

    private static func info(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
