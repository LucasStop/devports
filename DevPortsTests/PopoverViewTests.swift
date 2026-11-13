import XCTest

@testable import DevPorts

@MainActor
final class PopoverViewTests: XCTestCase {
    /// B1: the MenuBarExtra rebuilds the view on every scan; that must not send the popover back to Portas.
    func testRebuildingTheViewKeepsTheTab() {
        let store = Store.preview([])
        store.tab = .apps
        _ = PopoverView(store: store)
        XCTAssertEqual(store.tab, .apps)
        _ = PopoverView(store: store, startOn: .terminal)
        XCTAssertEqual(store.tab, .terminal)
    }

    func testTerminalInThePopoverOpensNoWindow() {
        let store = Store.preview([])
        var opened = 0
        store.showTerminal(placement: .popover) { opened += 1 }
        XCTAssertEqual(store.tab, .terminal)
        XCTAssertEqual(store.terminal.host, .popover)
        XCTAssertEqual(opened, 0)
    }

    /// B5: set to Janela, the sessions move to the window and the tab shows the notice.
    func testTerminalInTheWindowOpensItOnce() {
        let store = Store.preview([])
        var opened = 0
        store.showTerminal(placement: .window) { opened += 1 }
        XCTAssertEqual(store.tab, .terminal)
        XCTAssertEqual(store.terminal.host, .window)
        XCTAssertEqual(opened, 1)
    }
}
