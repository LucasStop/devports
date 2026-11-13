import XCTest

@testable import DevPorts

/// The real system calls, on processes this test spawns and nothing else; tearDown kills whatever is left.
final class IntegrationTests: XCTestCase {
    private var children: [Process] = []

    override func tearDown() {
        for child in children where child.isRunning {
            kill(child.processIdentifier, SIGCONT)
            kill(child.processIdentifier, SIGKILL)
        }
        children = []
    }

    private func spawn(_ path: String, _ arguments: [String]) throws -> Process {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: path)
        child.arguments = arguments
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        children.append(child)
        return child
    }

    private func state(_ pid: pid_t) -> String {
        ProcessScanner.run("/bin/ps", ["-o", "stat=", "-p", String(pid)]).trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    private func eventually(within seconds: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(seconds)
        while Date.now < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
    }

    func testStopContinueAndTerminateARealProcess() throws {
        let sleeper = try spawn("/bin/sleep", ["60"])
        let pid = sleeper.processIdentifier
        let started = try XCTUnwrap(ProcessKiller.startTime(pid))
        let killer = ProcessKiller()

        XCTAssertEqual(killer.suspend(pid: pid, startedAt: started), .sent(SIGSTOP))
        XCTAssertTrue(eventually { state(pid).contains("T") })
        XCTAssertEqual(killer.resume(pid: pid, startedAt: started), .sent(SIGCONT))
        XCTAssertTrue(eventually { !state(pid).contains("T") })

        // A stopped process holds TERM pending; terminate continues it first, so it really exits.
        _ = killer.suspend(pid: pid, startedAt: started)
        XCTAssertTrue(eventually { state(pid).contains("T") })
        XCTAssertEqual(killer.terminate(pid: pid, startedAt: started, suspended: true), .sent(SIGTERM))
        XCTAssertTrue(eventually(within: 2) { !sleeper.isRunning })
        XCTAssertEqual(killer.suspend(pid: pid, startedAt: started), .gone)
    }

    func testOtherStartTimeGetsNoSignal() throws {
        let pid = try spawn("/bin/sleep", ["60"]).processIdentifier
        XCTAssertEqual(ProcessKiller().suspend(pid: pid, startedAt: .distantPast), .pidReused)
        XCTAssertFalse(state(pid).contains("T"))
    }

    func testActivityScanFindsThisProcess() throws {
        let me = try XCTUnwrap(ActivityScanner.scan().first { $0.pid == getpid() })
        XCTAssertEqual(me.ppid, getppid())
        XCTAssertEqual(me.uid, getuid())
        let started = try XCTUnwrap(ProcessKiller.startTime(getpid()))
        XCTAssertEqual(Int(me.startedAt.timeIntervalSince1970), Int(started.timeIntervalSince1970))
        XCTAssertGreaterThan(me.memoryBytes, 0)
    }

    func testPortScanFindsALoopbackListenerAndItsPause() throws {
        let port = try freePort()
        let listener = try spawn("/usr/bin/nc", ["-l", "127.0.0.1", String(port)])
        let pid = listener.processIdentifier
        func row() -> DevProcess? { ProcessScanner.scan().first { $0.pid == pid } }

        XCTAssertTrue(eventually { row()?.ports.map(\.number) == [port] })
        XCTAssertEqual(row()?.ports.first?.isExposed, false)
        XCTAssertEqual(row()?.isSuspended, false)

        kill(pid, SIGSTOP)
        XCTAssertTrue(eventually { row()?.isSuspended == true })
        XCTAssertEqual(row()?.ports.map(\.number), [port], "a stopped server keeps its port")
    }

    /// A port the kernel just handed out, so the listener never collides with a dev server (3000 and 3001 included).
    private func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0
            }
        }
        guard bound else { throw XCTSkip("no free loopback port") }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
