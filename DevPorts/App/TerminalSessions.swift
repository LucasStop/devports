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

        let id = UUID()
        let title: String
        let folder: String
        @ObservationIgnored let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 860, height: 480))
        fileprivate(set) var status = Status.running

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
        session.view.processDelegate = session
        session.view.startProcess(
            executable: "/bin/zsh", environment: Terminal.getEnvironmentVariables(termName: "xterm-256color"),
            execName: "-zsh", currentDirectory: folder)
        if let command { session.view.send(txt: command + "\r") }
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
}

extension TerminalSessions.Session: @preconcurrency LocalProcessTerminalViewDelegate {
    func processTerminated(source: TerminalView, exitCode: Int32?) { status = .exited(exitCode) }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
