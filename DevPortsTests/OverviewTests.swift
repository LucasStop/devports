import XCTest

@testable import DevPorts

/// Slice 2 extra cases, not in the plan's table: what the popover lists for a scan, a query and the system toggle.
final class OverviewTests: XCTestCase {
    func testDefaultViewShowsDevPortsAndHidesSystemAndDynamicOnes() {
        let processes = [
            process(pid: 1, label: "next dev", ports: [3000]),
            process(pid: 2, label: "ControlCenter", group: "Sistema", ports: [7000, 5000], isDev: false),
            process(pid: 3, label: "expo run:ios", ports: [8081, 49717]),
            process(pid: 4, label: "tooling-daemon", group: "Sistema", ports: [53000]),
        ]
        let overview = Overview(processes: processes)
        XCTAssertEqual(overview.ports.map(\.port.number), [3000, 8081])
        XCTAssertEqual(overview.hiddenCount, 4)
        // A dev process whose only port is dynamic falls back to its group.
        XCTAssertEqual(overview.groups.map(\.name), ["Sistema"])

        let everything = Overview(processes: processes, showSystem: true)
        XCTAssertEqual(everything.ports.map(\.port.number), [3000, 5000, 7000, 8081, 49717, 53000])
        XCTAssertTrue(everything.groups.isEmpty)
    }

    func testGroupsAndTheirProcessesAreSortedByMemory() {
        let processes = [
            process(pid: 1, group: "a", memoryMB: 10),
            process(pid: 2, group: "b", memoryMB: 30),
            process(pid: 3, group: "a", memoryMB: 25),
        ]
        let groups = Overview(processes: processes).groups
        XCTAssertEqual(groups.map(\.name), ["a", "b"])
        XCTAssertEqual(groups.first?.processes.map(\.pid), [3, 1])
    }

    func testNumericSearchMatchesPortOrPidIncludingHiddenRows() {
        let processes = [
            process(pid: 700, label: "ControlCenter", group: "Sistema", ports: [5000, 7000], isDev: false),
            process(pid: 5000, label: "gradle-daemon-main", group: "~/.gradle"),
        ]
        let byPort = Overview(processes: processes, query: ":7000")
        XCTAssertEqual(byPort.ports.map(\.id), ["700:7000"])
        XCTAssertTrue(byPort.groups.isEmpty)

        let byPortOrPid = Overview(processes: processes, query: "5000")
        XCTAssertEqual(byPortOrPid.ports.map(\.id), ["700:5000"])
        XCTAssertEqual(byPortOrPid.groups.first?.processes.map(\.pid), [5000])
    }

    func testTextSearchMatchesLabelExecutableOrGroupName() {
        let processes = [
            process(pid: 1, label: "next", group: "oparceiro_panel"),
            process(pid: 2, label: "tsserver", group: "oparceiro_panel"),
            process(pid: 3, label: "gradle-daemon-main", executable: "java", group: "~/.gradle"),
        ]
        XCTAssertEqual(Overview(processes: processes, query: "NEXT").groups.flatMap { $0.processes.map(\.pid) }, [1])
        XCTAssertEqual(Overview(processes: processes, query: "parceiro").groups.first?.processes.count, 2)
        XCTAssertEqual(Overview(processes: processes, query: "java").groups.map(\.name), ["~/.gradle"])
    }

    func testSearchedPortWithNoRowIsFreeUnlessAnotherUserListensOnIt() {
        func searched(_ query: String) -> Overview.SearchedPort? {
            Overview(processes: [], query: query, isPortTaken: { $0 == 80 }).searchedPort
        }
        XCTAssertEqual(searched("4000"), Overview.SearchedPort(number: 4000, isFree: true))
        XCTAssertEqual(searched("80"), Overview.SearchedPort(number: 80, isFree: false))
        XCTAssertNil(searched("70000"))
        XCTAssertNil(searched("next"))
    }

    private func process(
        pid: Int32, label: String = "node", executable: String = "node", group: String = "app", ports: [Int] = [],
        isDev: Bool = true, memoryMB: Int64 = 10
    ) -> DevProcess {
        DevProcess(
            pid: pid, ppid: 1, executable: executable, argv: [executable], label: label, cwd: nil, project: nil,
            group: group, ports: ports.map { ListeningPort(number: $0, isExposed: false) },
            memoryBytes: memoryMB * 1_048_576, startedAt: .distantPast, isDev: isDev)
    }
}
