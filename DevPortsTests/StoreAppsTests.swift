import XCTest

@testable import DevPorts

@MainActor
final class StoreAppsTests: XCTestCase {
    private struct NoScan: ProcessScanning { func scan() -> [DevProcess] { [] } }
    private struct NoActivity: ActivityScanning { func scan() -> [ProcessNode] { [] } }

    /// Each scan reports 0.01 s more CPU, the `ps time` granularity.
    private final class GrowingCPU: ActivityScanning, @unchecked Sendable {
        private let lock = NSLock()
        private var seconds = 0.0
        func scan() -> [ProcessNode] {
            lock.lock()
            defer { lock.unlock() }
            seconds += 0.01
            return [
                ProcessNode(
                    pid: 10, ppid: 1, uid: 501, path: "/bin/yes", memoryBytes: 0, cpuSeconds: seconds,
                    startedAt: .distantPast, isSuspended: false)
            ]
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func recordingKiller(errno result: Int32 = 0) -> (ProcessKiller, () -> [(pid_t, Int32)], () -> Void) {
        var signals: [(pid_t, Int32)] = []
        let started = t0
        let killer = ProcessKiller(
            send: {
                signals.append(($0, $1))
                return result
            }, startTime: { _ in started })
        return (killer, { signals }, { signals = [] })
    }

    private func node(_ pid: Int32, parent: Int32 = 1, suspended: Bool = false) -> ProcessNode {
        ProcessNode(
            pid: pid, ppid: parent, uid: 501, path: "/Applications/Foo.app/Contents/MacOS/Foo \(pid)", memoryBytes: 0,
            cpuSeconds: 0, startedAt: t0, isSuspended: suspended)
    }

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

    /// B2: a refresh a few ms after another must not divide 0.01 s by a few ms (hundreds of %).
    func testBackToBackScansDoNotComputeCPU() async {
        let store = Store(scanner: NoScan(), autoRefresh: false, activityScanner: GrowingCPU())
        store.isAppsTabOpen = true
        await store.refresh()
        await store.refresh()
        XCTAssertNil(store.cpu)
        XCTAssertEqual(store.activityNodes.first?.cpuSeconds ?? 0, 0.02, accuracy: 0.001)
    }

    /// B3: a dev server paused from its row is continued on quit too.
    func testQuitContinuesPausedDevRow() {
        let (killer, signals, reset) = recordingKiller()
        let store = Store(scanner: NoScan(), autoRefresh: false, activityScanner: NoActivity(), killer: killer)
        let server = DevProcess(
            pid: 4242, ppid: 1, executable: "node", argv: ["node"], label: "next dev", cwd: nil, project: "app",
            group: "app", ports: [], memoryBytes: 0, startedAt: t0, isDev: true)

        store.suspend(server)
        reset()
        store.resumeAllPaused()
        XCTAssertEqual(signals().map(\.0), [4242])
        XCTAssertEqual(signals().map(\.1), [SIGCONT])

        store.suspend(server)
        store.resume(server)
        reset()
        store.resumeAllPaused()
        XCTAssertTrue(signals().isEmpty)
    }

    /// B4: a helper already stopped before DevPorts paused the app gets neither STOP nor, on quit, CONT.
    func testAlreadySuspendedMemberIsLeftAlone() {
        let (killer, signals, reset) = recordingKiller()
        let store = Store(scanner: NoScan(), autoRefresh: false, activityScanner: NoActivity(), killer: killer)
        let app = Activity.apps(
            nodes: [node(10), node(11, parent: 10, suspended: true)], cpu: nil, me: 501, ownPid: 1, showSystem: false)[
                0]

        store.suspendApp(app)
        XCTAssertEqual(signals().map(\.0), [10])
        reset()
        store.resumeAllPaused()
        XCTAssertEqual(signals().map(\.0), [10])
    }

    func testResumingAnAppClearsItFromQuit() {
        let (killer, signals, reset) = recordingKiller()
        let store = Store(scanner: NoScan(), autoRefresh: false, activityScanner: NoActivity(), killer: killer)
        let app = Activity.apps(nodes: [node(10)], cpu: nil, me: 501, ownPid: 1, showSystem: false)[0]

        store.suspendApp(app)
        store.resumeApp(app)
        reset()
        store.resumeAllPaused()
        XCTAssertTrue(signals().isEmpty)
    }

    func testDeniedPauseNamesTheProcessAndIsNotRecorded() {
        let (killer, signals, reset) = recordingKiller(errno: EPERM)
        let store = Store(scanner: NoScan(), autoRefresh: false, activityScanner: NoActivity(), killer: killer)
        let app = Activity.apps(nodes: [node(10)], cpu: nil, me: 501, ownPid: 1, showSystem: false)[0]

        store.suspendApp(app)
        XCTAssertEqual(store.banner?.contains("pid 10"), true)
        reset()
        store.resumeAllPaused()
        XCTAssertTrue(signals().isEmpty)
    }
}
