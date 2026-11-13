import XCTest

@testable import DevPorts

final class PopoverSizesTests: XCTestCase {
    func testDefaultIs440WithAutomaticHeight() {
        let size = PopoverSizes().size(for: .ports, terminalHost: .popover)
        XCTAssertEqual(size, PanelSize(width: 440, height: nil))
    }

    func testSameSizeAppliesToEveryTab() {
        var sizes = PopoverSizes()
        sizes.all = PanelSize(width: 500, height: 400)
        for tab in PopoverTab.allCases {
            XCTAssertEqual(sizes.size(for: tab, terminalHost: .popover), PanelSize(width: 500, height: 400))
        }
    }

    func testPerTabSizes() {
        var sizes = PopoverSizes()
        sizes.same = false
        sizes.apps = PanelSize(width: 480, height: 520)
        sizes.terminal = PanelSize(width: 560, height: 420)
        XCTAssertEqual(sizes.size(for: .ports, terminalHost: .popover).width, 440)
        XCTAssertEqual(sizes.size(for: .apps, terminalHost: .popover), PanelSize(width: 480, height: 520))
        XCTAssertEqual(sizes.size(for: .terminal, terminalHost: .popover), PanelSize(width: 560, height: 420))
    }

    func testTerminalSizeIgnoredWhenItOpensInWindow() {
        var sizes = PopoverSizes()
        sizes.same = false
        sizes.terminal = PanelSize(width: 560, height: 420)
        XCTAssertEqual(sizes.size(for: .terminal, terminalHost: .window), PanelSize())
    }

    func testValuesAreClampedToTheRanges() {
        var sizes = PopoverSizes()
        sizes.all = PanelSize(width: 2000, height: 10)
        XCTAssertEqual(sizes.size(for: .ports, terminalHost: .popover), PanelSize(width: 720, height: 300))
    }

    func testRawValueRoundTrips() {
        var sizes = PopoverSizes()
        sizes.same = false
        sizes.apps = PanelSize(width: 480, height: 520)
        XCTAssertEqual(PopoverSizes(rawValue: sizes.rawValue), sizes)
    }

    func testGarbageRawValueFallsBack() {
        XCTAssertNil(PopoverSizes(rawValue: "not json"))
    }

    @MainActor
    func testHostSwitchKeepsSessions() {
        let terminal = TerminalSessions()
        XCTAssertEqual(terminal.host, .popover)
        terminal.host = .window
        terminal.host = .popover
        XCTAssertTrue(terminal.sessions.isEmpty)
    }
}
