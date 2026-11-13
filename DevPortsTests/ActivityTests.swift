import XCTest

@testable import DevPorts

final class ActivityTests: XCTestCase {
    private let me: UInt32 = 501
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func node(
        _ pid: Int32, _ ppid: Int32, _ path: String, uid: UInt32 = 501, mem: Int64 = 1_048_576, cpu: Double = 0,
        stopped: Bool = false
    ) -> ProcessNode {
        ProcessNode(
            pid: pid, ppid: ppid, uid: uid, path: path, memoryBytes: mem, cpuSeconds: cpu,
            startedAt: t0.addingTimeInterval(Double(pid)), isSuspended: stopped)
    }

    private let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    private let helper =
        "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"

    private func apps(_ nodes: [ProcessNode], showSystem: Bool = false, query: String = "", sort: Activity.Sort = .cpu)
        -> [Activity.App]
    {
        Activity.apps(
            nodes: nodes, cpu: nil, me: me, ownPid: 9999, showSystem: showSystem, query: query, sort: sort)
    }

    func testParsesPSLineWithCpuTimeAndState() throws {
        let line =
            "  812 1 501 20480 T 1:02:03.5 Mon Sep 21 12:27:45 2026 /Applications/Visual Studio Code.app/Contents/MacOS/Electron\n"
        let node = try XCTUnwrap(ActivityScanner.parse(line).first)
        XCTAssertEqual(node.pid, 812)
        XCTAssertEqual(node.uid, 501)
        XCTAssertEqual(node.cpuSeconds, 3723.5)
        XCTAssertTrue(node.isSuspended)
        XCTAssertEqual(node.executable, "Electron")
    }

    func testCpuTimeFormats() {
        XCTAssertEqual(ActivityScanner.cpuSeconds("0:01.25"), 1.25)
        XCTAssertEqual(ActivityScanner.cpuSeconds("12:30.00"), 750)
        XCTAssertEqual(ActivityScanner.cpuSeconds("2-00:00:10"), 172_810)
        XCTAssertNil(ActivityScanner.cpuSeconds("abc"))
    }

    // Helpers whose parent is the app, and ones launchd started, all land under the one bundle.
    func testGroupsHelpersUnderTheAppBundle() {
        let nodes = [node(100, 1, chrome), node(101, 100, helper), node(102, 1, helper), node(200, 1, "/usr/bin/vim")]
        let result = apps(nodes)
        let app = result.first { $0.name == "Google Chrome" }
        XCTAssertEqual(app?.members.map(\.pid), [100, 101, 102])
        XCTAssertEqual(result.count, 2)
    }

    func testPlainProcessGroupsUnderItsRootWithChildren() {
        let result = apps([node(300, 1, "/bin/zsh"), node(301, 300, "/usr/bin/node"), node(302, 301, "/usr/bin/node")])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "zsh")
        XCTAssertEqual(result[0].members.count, 3)
    }

    func testProtectedGroupsHaveNoButton() {
        let finder = "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"
        XCTAssertEqual(apps([node(400, 1, finder)])[0].kind, .protected)
        XCTAssertEqual(apps([node(401, 1, "/usr/sbin/WindowServer")], showSystem: true)[0].kind, .protected)
    }

    func testOwnAppAndItsAncestorsAreProtected() {
        let nodes = [
            node(500, 1, "/Applications/Terminal.app/Contents/MacOS/Terminal"), node(501, 500, "/bin/zsh"),
            node(9999, 501, "/Applications/DevPorts.app/Contents/MacOS/DevPorts"),
        ]
        let result = Activity.apps(nodes: nodes, cpu: nil, me: me, ownPid: 9999, showSystem: false)
        XCTAssertEqual(result.map(\.kind), [.protected])
    }

    func testOtherUsersHiddenUnlessShowSystemAndThenLocked() {
        let nodes = [node(600, 1, "/usr/libexec/mds", uid: 0)]
        XCTAssertTrue(apps(nodes).isEmpty)
        XCTAssertEqual(apps(nodes, showSystem: true)[0].kind, .other)
    }

    func testCpuPercentUsesGainedSecondsOverInterval() {
        let before = [node(700, 1, chrome, cpu: 10)]
        let now = [node(700, 1, chrome, cpu: 11), node(701, 1, helper, cpu: 5)]
        let percent = Activity.cpuPercent(now: now, previous: [before[0].key: 10], interval: 2)
        XCTAssertEqual(percent[now[0].key], 50)
        XCTAssertEqual(percent[now[1].key], 0)
    }

    func testSuspendedProcessGainsNoCpu() {
        let stopped = node(710, 1, chrome, cpu: 10, stopped: true)
        XCTAssertEqual(Activity.cpuPercent(now: [stopped], previous: [stopped.key: 10], interval: 5)[stopped.key], 0)
    }

    func testSortsByCpuMemoryAndName() {
        let a = node(800, 1, "/Applications/Alpha.app/Contents/MacOS/a", mem: 3_000_000)
        let b = node(801, 1, "/Applications/Beta.app/Contents/MacOS/b", mem: 9_000_000)
        let cpu = [a.key: 50.0, b.key: 5.0]
        func names(_ sort: Activity.Sort) -> [String] {
            Activity.apps(nodes: [a, b], cpu: cpu, me: me, ownPid: 1, showSystem: false, sort: sort).map(\.name)
        }
        XCTAssertEqual(names(.cpu), ["Alpha", "Beta"])
        XCTAssertEqual(names(.memory), ["Beta", "Alpha"])
        XCTAssertEqual(names(.name), ["Alpha", "Beta"])
    }

    func testQueryMatchesNameOrPid() {
        let nodes = [node(900, 1, chrome), node(901, 1, "/usr/bin/vim")]
        XCTAssertEqual(apps(nodes, query: "chrome").map(\.name), ["Google Chrome"])
        XCTAssertEqual(apps(nodes, query: "901").map(\.name), ["vim"])
    }

    func testSuspendedWhenAnyMemberIsStopped() {
        let result = apps([node(950, 1, chrome, stopped: true), node(951, 950, helper)])
        XCTAssertTrue(result[0].isSuspended)
    }

    /// B6: the badge follows the root, as the filter does, even when an older member is the user's own.
    func testSystemBadgeFollowsTheRoot() {
        let result = apps([node(900, 1, "/usr/sbin/sshd", uid: 0), node(800, 900, "/bin/zsh")], showSystem: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].members.first?.pid, 800)
        XCTAssertTrue(result[0].isSystem)
        XCTAssertFalse(apps([node(950, 1, chrome)])[0].isSystem)
    }

    func testParentCycleStillGroups() {
        XCTAssertFalse(apps([node(10, 11, "/bin/a"), node(11, 10, "/bin/b")]).isEmpty)
    }

    /// Known limit: XPC services are launchd's children, so Safari's web content is its own row, not paused with it.
    func testXPCServiceUnderLaunchdIsItsOwnApp() {
        let webContent =
            "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
        let result = apps([node(600, 1, "/Applications/Safari.app/Contents/MacOS/Safari"), node(700, 1, webContent)])
        XCTAssertEqual(Set(result.map(\.name)), ["Safari", "com.apple.WebKit.WebContent"])
    }
}
