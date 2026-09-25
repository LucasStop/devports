import AppKit
import Observation
import SwiftTerm

/// Shell sessions of the Terminal window. Each one owns its terminal view, so switching tabs never ends a process.
@Observable @MainActor
final class TerminalSessions {
    @Observable @MainActor
    final class Session: Identifiable {
        enum Status: Equatable {
            case running
            case exited(Int32?)
        }

        /// A command line the shell runs in the foreground, with everything it spawned (one process group).
        struct Job: Equatable {
            let pid: pid_t
            let startedAt: Date
            let command: String
        }

        struct Finished: Equatable {
            let command: String
            let duration: TimeInterval
        }

        let id = UUID()
        let title: String
        let folder: String
        @ObservationIgnored let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 860, height: 480))
        fileprivate(set) var status = Status.running
        fileprivate(set) var job: Job?
        fileprivate(set) var ports: [ListeningPort] = []
        /// When Parar sent Ctrl-C; the bar offers Forçar 5 s later.
        fileprivate(set) var stopSent: Date?
        fileprivate(set) var finished: Finished?
        /// What DevPorts typed; it names the next job, since node may rewrite the argv it would be read from.
        @ObservationIgnored fileprivate var typed: String?
        @ObservationIgnored fileprivate var restartPending = false

        var bar: SessionBar {
            SessionBar(status: status, job: job, ports: ports, stopSent: stopSent, finished: finished)
        }

        init(title: String, folder: String) {
            self.title = title
            self.folder = folder
        }
    }

    private(set) var sessions: [Session] = []
    /// nil is the Ações tab.
    var selected: Session.ID?

    var running: [Session] { sessions.filter { $0.status == .running } }

    /// A login zsh in `folder`, so the PATH from .zprofile/.zshrc (nvm, pnpm) is there, which a GUI app lacks. The
    /// command is typed into it, and the shell stays after Ctrl-C.
    func open(title: String, folder: String, command: String? = nil) {
        let session = Session(title: title, folder: folder)
        session.view.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        TerminalTheme.apply(to: session.view)
        session.view.processDelegate = session
        session.view.startProcess(
            executable: "/bin/zsh", environment: Terminal.getEnvironmentVariables(termName: "xterm-256color"),
            execName: "-zsh", currentDirectory: folder)
        if let command { type(command, in: session) }
        sessions.append(session)
        selected = session.id
    }

    /// Hangs up the shell, as closing a terminal tab does: zsh passes SIGHUP on to its jobs (`npm run dev`). The
    /// TERM that SwiftTerm's terminate() sends alone is ignored by an interactive zsh, and the job outlived the tab.
    func close(_ session: Session) {
        if session.status == .running {
            kill(session.view.process.shellPid, SIGHUP)
            session.view.terminate()
        }
        sessions.removeAll { $0.id == session.id }
        if selected == session.id { selected = sessions.last?.id }
    }

    func closeAll() {
        sessions.forEach(close)
    }

    func stop(_ session: Session) {
        session.stopSent = .now
        session.view.send(txt: "\u{03}")
    }

    /// With a job running, Ctrl-C now and the command again when `poll` sees the job gone; otherwise reruns the
    /// last command.
    func restart(_ session: Session) {
        if session.job != nil {
            session.restartPending = true
            stop(session)
        } else if let finished = session.finished {
            type(finished.command, in: session)
        }
    }

    /// Reads each tab's foreground job from the pty, which is the shell itself while it waits at the prompt. Ports
    /// come from the latest scan, matched by process group so a server spawned under `sh -c` still counts.
    func poll(processes: [DevProcess]) {
        for session in sessions where session.status == .running {
            let group = tcgetpgrp(session.view.process.childfd)
            if group > 0, group != session.view.process.shellPid {
                if session.job?.pid != group, let start = ProcessKiller.startTime(group) {
                    let argv = ProcessScanner.argvs(for: [group])[group] ?? []
                    let command = session.typed ?? (argv.isEmpty ? "pid \(group)" : Restart.command(argv: argv))
                    session.typed = nil
                    session.job = Session.Job(pid: group, startedAt: start, command: command)
                    session.finished = nil
                }
                let ports = processes.filter { !$0.ports.isEmpty && ProcessKiller.processGroup($0.pid) == group }
                    .flatMap(\.ports).filter { !$0.isDynamic }
                if session.ports != ports { session.ports = ports }
            } else if let job = session.job {
                session.finished = Session.Finished(
                    command: job.command, duration: Date.now.timeIntervalSince(job.startedAt))
                session.job = nil
                session.ports = []
                session.stopSent = nil
                if session.restartPending {
                    session.restartPending = false
                    type(job.command, in: session)
                }
            }
        }
    }

    private func type(_ command: String, in session: Session) {
        session.typed = command
        session.view.send(txt: command + "\r")
    }
}

/// What the bar under a tab shows, derived from the session alone so it can be tested without a terminal.
enum SessionBar: Equatable {
    case running(TerminalSessions.Session.Job, ports: [ListeningPort])
    case stopping(TerminalSessions.Session.Job, since: Date)
    case finished(TerminalSessions.Session.Finished)
    case idle
    case shellExited(Int32?)

    init(
        status: TerminalSessions.Session.Status, job: TerminalSessions.Session.Job?, ports: [ListeningPort],
        stopSent: Date?, finished: TerminalSessions.Session.Finished?
    ) {
        if case .exited(let code) = status {
            self = .shellExited(code)
        } else if let job, let stopSent {
            self = .stopping(job, since: stopSent)
        } else if let job {
            self = .running(job, ports: ports)
        } else if let finished {
            self = .finished(finished)
        } else {
            self = .idle
        }
    }
}

/// DESIGN.md's terminal colors, dark or light after the system appearance when the session opens.
@MainActor
private enum TerminalTheme {
    static func apply(to view: LocalProcessTerminalView) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let (background, foreground, caret, ansi) =
            isDark
            ? (
                0x14161A, 0xD7DAE0, 0x3DD68C,
                [
                    0x1C1F24, 0xFF6B6B, 0x3DD68C, 0xFFB547, 0x6CB6FF, 0xD2A8FF, 0x56D4DD, 0xD7DAE0,
                    0x5C6370, 0xFF8A8A, 0x6BE3A8, 0xFFD27A, 0x9CCBFF, 0xE2C5FF, 0x8BE9F0, 0xFFFFFF,
                ]
            )
            : (
                0xFBFBFA, 0x24292F, 0x17803F,
                [
                    0x24292F, 0xC62828, 0x17803F, 0x9A6700, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781,
                    0x57606A, 0xE5534B, 0x1F9D55, 0xB08800, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F,
                ]
            )
        view.installColors(ansi.map(color))
        view.nativeBackgroundColor = nsColor(background)
        view.nativeForegroundColor = nsColor(foreground)
        view.caretColor = nsColor(caret)
    }

    private static func color(_ hex: Int) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((hex >> 16) & 0xFF) * 257, green: UInt16((hex >> 8) & 0xFF) * 257,
            blue: UInt16(hex & 0xFF) * 257)
    }

    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension TerminalSessions.Session: @preconcurrency LocalProcessTerminalViewDelegate {
    func processTerminated(source: TerminalView, exitCode: Int32?) { status = .exited(exitCode) }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
