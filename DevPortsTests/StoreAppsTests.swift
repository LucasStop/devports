import XCTest

@testable import DevPorts

@MainActor
final class StoreAppsTests: XCTestCase {
    private struct NoScan: ProcessScanning { func scan() -> [DevProcess] { [] } }
    private struct NoActivity: ActivityScanning { func scan() -> [ProcessNode] { [] } }

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testQuitContinuesWhatWasPausedAndNothingElse() {
        var signals: [(pid_t, Int32)] = []
        let started = t0
        let killer = ProcessKiller(
            send: {
                signals.append(($0, $1))
                return 0
            }, startTime: { _ in started })
        let store = Store(scanner: NoScan(), autoRefresh: false, activityScanner: NoActivity(), killer: killer)
        let nodes = [
            ProcessNode(
                pid: 10, ppid: 1, uid: 501, path: "/Applications/Foo.app/Contents/MacOS/Foo", memoryBytes: 0,
                cpuSeconds: 0, startedAt: started, isSuspended: false),
            ProcessNode(
                pid: 11, ppid: 10, uid: 501, path: "/Applications/Foo.app/Contents/MacOS/Foo Helper", memoryBytes: 0,
                cpuSeconds: 0, startedAt: started, isSuspended: false),
        ]
        let app = Activity.apps(nodes: nodes, cpu: nil, me: 501, ownPid: 1, showSystem: false)[0]

        store.suspendApp(app)
        XCTAssertEqual(signals.map(\.1), [SIGSTOP, SIGSTOP])
        signals = []
        store.resumeAllPaused()
        XCTAssertEqual(signals.map(\.1), [SIGCONT, SIGCONT])
        signals = []
        store.resumeAllPaused()
        XCTAssertTrue(signals.isEmpty)
    }
}
