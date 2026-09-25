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
    /// A restart waiting on its inline confirmation, which shows the exact command.
    private(set) var pendingRestart: (process: DevProcess, plan: Restart.Plan)?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private let killer = ProcessKiller()
    @ObservationIgnored let terminal = TerminalSessions()

    @ObservationIgnored private var isPopoverOpen = false
    /// Session bars show a job's ports, so the scan keeps the popover's pace while the Terminal window is open.
    @ObservationIgnored var isTerminalOpen = false {
        didSet { restartPolling() }
    }

    init() { restartPolling() }

    var devPortCount: Int { Overview(processes: processes).ports.count }

    /// Restarts polling with a scan right away, so opening the popover never shows data 30 s old.
    func setPopoverOpen(_ isOpen: Bool) {
        isPopoverOpen = isOpen
        restartPolling()
    }

    private func restartPolling() {
        let interval = isPopoverOpen || isTerminalOpen ? 5 : 30
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(interval))
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

    /// Opens a shell tab in `folder`, typing `command` into it; the caller brings up the Terminal window.
    func openTerminal(title: String, folder: String, command: String? = nil) {
        terminal.open(title: title, folder: folder, command: command)
        log.append(LogEntry(command: "cd \(folder)" + (command.map { " && \($0)" } ?? ""), result: "aba \(title)"))
    }

    func prepareRestart(_ process: DevProcess) async {
        let pid = process.pid
        guard let plan = await Task.detached(operation: { ProcessScanner.restartPlan(for: pid) }).value else {
            banner = "Não deu para ler o comando que iniciou \(process.label)."
            return
        }
        pendingRestart = (process, plan)
    }

    func cancelRestart() { pendingRestart = nil }

    /// TERMs the root command and everything under it, waits up to 5 s and runs the command again in a Terminal tab.
    /// Returns false, without relaunching, if anything is still alive; its row then offers "Forçar".
    func confirmRestart() async -> Bool {
        guard let (process, plan) = pendingRestart else { return false }
        pendingRestart = nil
        for target in plan.targets {
            let outcome = killer.terminate(pid: target.pid, startedAt: target.startedAt)
            log.append(
                LogEntry(
                    command: "kill -TERM \(target.pid)  # reinício de \(process.label)", result: Self.describe(outcome))
            )
        }
        var alive = plan.targets
        for _ in 0..<10 where !alive.isEmpty {
            try? await Task.sleep(for: .milliseconds(500))
            alive = alive.filter { kill($0.pid, 0) == 0 }
        }
        await refresh()
        guard alive.isEmpty else {
            for target in alive where stopping[target.pid] == nil { stopping[target.pid] = .unresponsive }
            banner =
                "Reinício cancelado: \(alive.count == 1 ? "1 processo não saiu" : "\(alive.count) processos não saíram") em 5 s."
            return false
        }
        openTerminal(
            title: "\(process.project ?? process.label) · reinício", folder: plan.folder, command: plan.command)
        return true
    }

    /// Ctrl-C, as if typed in the tab: the shell stays, and only its foreground job gets SIGINT.
    func stopJob(in session: TerminalSessions.Session) {
        guard let job = session.job else { return }
        terminal.stop(session)
        log.append(LogEntry(command: "^C  # pid \(job.pid), aba \(session.title)", result: "enviado"))
    }

    /// Stops the job and types its command again in the same tab once it has exited; or reruns a finished one.
    func restartJob(in session: TerminalSessions.Session) {
        terminal.restart(session)
        log.append(LogEntry(command: "^C && !!  # aba \(session.title)", result: "reinício na mesma aba"))
    }

    func forceJob(in session: TerminalSessions.Session) {
        guard let job = session.job else { return }
        let outcome = ProcessKiller.killGroup(job.pid, startedAt: job.startedAt)
        log.append(LogEntry(command: "kill -KILL -\(job.pid)  # aba \(session.title)", result: Self.describe(outcome)))
        if outcome == .notPermitted { banner = "Sem permissão para encerrar o pid \(job.pid)." }
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
