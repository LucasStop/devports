import AppKit
import Foundation
import Observation

/// The latest scan, plus the actions taken on it. Refreshed every 5 s while the popover is open and every 30 s while
/// it is closed, when only the menu bar counter needs it.
@Observable @MainActor
final class Store {
    struct LogEntry: Identifiable {
        let id = UUID()
        let date = Date.now
        /// A shell command that reproduces the action; never the full argv, which may carry tokens.
        let command: String
        let result: String
    }

    private(set) var processes: [DevProcess] = []
    enum Stopping {
        case waiting
        /// Still alive 5 s after the signal: the row offers "Forçar".
        case unresponsive
    }

    /// Signaled pids that are still alive.
    private(set) var stopping: [Int32: Stopping] = [:]
    private(set) var log: [LogEntry] = []
    /// Footer error, dismissed by the user.
    var banner: String?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private let killer = ProcessKiller()

    init() { setPopoverOpen(false) }

    var devPortCount: Int { Overview(processes: processes).ports.count }

    /// Restarts polling with a scan right away, so opening the popover never shows data 30 s old.
    func setPopoverOpen(_ isOpen: Bool) {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(isOpen ? 5 : 30))
            }
        }
    }

    func refresh() async {
        processes = await Task.detached(priority: .userInitiated) { ProcessScanner.scan() }.value
        let alive = Set(processes.map(\.pid))
        stopping = stopping.filter { alive.contains($0.key) }
    }

    /// TERM the first time, KILL when a pid already got TERM ("Forçar"). Rescans every second for 6 s so rows leave
    /// as soon as their process exits, and flags the survivors at 5 s.
    func terminate(_ targets: [DevProcess]) {
        var signaled: [Int32] = []
        for process in targets {
            let outcome = killer.terminate(process)
            let signal = outcome == .sent(SIGKILL) ? "KILL" : "TERM"
            let note = [process.label, process.project.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            log.append(LogEntry(command: "kill -\(signal) \(process.pid)  # \(note)", result: Self.describe(outcome)))
            switch outcome {
            case .sent:
                stopping[process.pid] = .waiting
                signaled.append(process.pid)
            case .gone: break
            case .notPermitted:
                banner =
                    "Sem permissão para encerrar \(process.label) (pid \(process.pid)). Ele pertence a outro usuário."
            case .pidReused:
                banner = "O pid \(process.pid) já é de outro processo. Nada foi enviado."
            }
        }
        Task {
            for second in 1...6 {
                try? await Task.sleep(for: .seconds(1))
                await refresh()
                if second == 5 {
                    for pid in signaled where stopping[pid] == .waiting { stopping[pid] = .unresponsive }
                }
            }
        }
    }

    func openInBrowser(_ port: Int) {
        let url = "http://localhost:\(port)"
        NSWorkspace.shared.open(URL(string: url)!)
        log.append(LogEntry(command: "open \(url)", result: "ok"))
    }

    func showInFinder(_ process: DevProcess) {
        guard let cwd = process.cwd else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
        log.append(LogEntry(command: "open \(cwd)", result: "ok"))
    }

    /// Copies the full argv to the clipboard; the log only names the process, since argv may carry tokens.
    func copyCommand(_ process: DevProcess) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(process.argv.joined(separator: " "), forType: .string)
        log.append(LogEntry(command: "pbcopy  # comando de \(process.label) (pid \(process.pid))", result: "ok"))
    }

    private static func describe(_ outcome: ProcessKiller.Outcome) -> String {
        switch outcome {
        case .sent: "enviado"
        case .gone: "o processo já tinha saído"
        case .notPermitted: "sem permissão"
        case .pidReused: "pid reciclado, nada enviado"
        }
    }
}
