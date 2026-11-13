import XCTest

@testable import DevPorts

final class ProcessKillerTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_790_000_000)
    private var sent: [Int32] = []

    // Case 17: the pid was recycled since the scan, so nothing is signaled.
    func testNoSignalWhenStartTimeChanged() {
        let killer = killer(startTime: started.addingTimeInterval(60))
        XCTAssertEqual(killer.terminate(process()), .pidReused)
        XCTAssertEqual(sent, [])
    }

    // Case 18: a second ✕ on a pid that already got TERM sends KILL.
    func testSecondTerminateForces() {
        let killer = killer(startTime: started.addingTimeInterval(0.4))
        XCTAssertEqual(killer.terminate(process()), .sent(SIGTERM))
        XCTAssertEqual(killer.terminate(process()), .sent(SIGKILL))
        XCTAssertEqual(sent, [SIGTERM, SIGKILL])
    }

    func testExitedProcessIsGone() {
        let killer = ProcessKiller(send: { _, _ in ESRCH }, startTime: { _ in nil })
        XCTAssertEqual(killer.terminate(process()), .gone)
    }

    func testSuspendAndResumeSendStopAndCont() {
        let killer = killer(startTime: started)
        XCTAssertEqual(killer.suspend(process()), .sent(SIGSTOP))
        XCTAssertEqual(killer.resume(process()), .sent(SIGCONT))
        XCTAssertEqual(sent, [SIGSTOP, SIGCONT])
    }

    func testSuspendSkipsRecycledPid() {
        let killer = killer(startTime: started.addingTimeInterval(60))
        XCTAssertEqual(killer.suspend(process()), .pidReused)
        XCTAssertEqual(sent, [])
    }

    func testSuspendOfOtherUsersProcessIsNotPermitted() {
        let killer = ProcessKiller(send: { _, _ in EPERM }, startTime: { _ in self.started })
        XCTAssertEqual(killer.suspend(process()), .notPermitted)
    }

    // A stopped process keeps TERM pending, so terminate continues it first.
    func testTerminateOfSuspendedProcessContinuesFirst() {
        var stopped = process()
        stopped.isSuspended = true
        let killer = killer(startTime: started)
        XCTAssertEqual(killer.terminate(stopped), .sent(SIGTERM))
        XCTAssertEqual(sent, [SIGCONT, SIGTERM])
    }

    /// `startTime` has microseconds; ps's lstart, which the scan keeps, only seconds.
    private func killer(startTime: Date) -> ProcessKiller {
        ProcessKiller(
            send: { [unowned self] _, signal in
                sent.append(signal)
                return 0
            }, startTime: { _ in startTime })
    }

    private func process() -> DevProcess {
        DevProcess(
            pid: 4242, ppid: 1, executable: "node", argv: ["node"], label: "next dev", cwd: nil, project: "app",
            group: "app", ports: [], memoryBytes: 0, startedAt: started, isDev: true)
    }
}
