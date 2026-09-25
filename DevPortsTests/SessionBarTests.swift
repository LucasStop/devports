import XCTest

@testable import DevPorts

final class SessionBarTests: XCTestCase {
    private let job = TerminalSessions.Session.Job(pid: 51234, startedAt: .distantPast, command: "yarn run dev")
    private let port = ListeningPort(number: 3000, isExposed: true)
    private let finished = TerminalSessions.Session.Finished(command: "yarn run dev", duration: 4)

    func testRunningJobShowsItsPorts() {
        XCTAssertEqual(bar(job: job, ports: [port]), .running(job, ports: [port]))
    }

    func testParar() {
        let sent = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(bar(job: job, stopSent: sent), .stopping(job, since: sent))
    }

    func testFinishedJobOffersRerun() {
        XCTAssertEqual(bar(finished: finished), .finished(finished))
    }

    func testShellAtThePrompt() {
        XCTAssertEqual(bar(), .idle)
    }

    // The shell itself exited: nothing below it can still be running.
    func testShellExitWins() {
        XCTAssertEqual(bar(status: .exited(1), job: job, finished: finished), .shellExited(1))
    }

    // A stale pid must never get the KILL meant for the job that started at another time.
    func testKillGroupChecksTheLeaderStartTime() {
        XCTAssertEqual(ProcessKiller.killGroup(getpid(), startedAt: .distantPast), .pidReused)
        XCTAssertEqual(ProcessKiller.processGroup(getpid()), getpgrp())
    }

    private func bar(
        status: TerminalSessions.Session.Status = .running, job: TerminalSessions.Session.Job? = nil,
        ports: [ListeningPort] = [], stopSent: Date? = nil, finished: TerminalSessions.Session.Finished? = nil
    ) -> SessionBar {
        SessionBar(status: status, job: job, ports: ports, stopSent: stopSent, finished: finished)
    }
}
