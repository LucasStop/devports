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
        guard let current = startTime(process.pid) else { return .gone }
        let key = "\(process.pid)@\(Int(process.startedAt.timeIntervalSince1970))"
        guard Int(current.timeIntervalSince1970) == Int(process.startedAt.timeIntervalSince1970) else {
            return .pidReused
        }
        let signal = terminated.contains(key) ? SIGKILL : SIGTERM
        switch send(process.pid, signal) {
        case 0:
            terminated.insert(key)
            return .sent(signal)
        case ESRCH: return .gone
        default: return .notPermitted
        }
    }

    static func startTime(_ pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
