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
        TerminalTheme.apply(to: session.view)
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
