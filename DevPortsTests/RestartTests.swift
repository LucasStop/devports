import XCTest

@testable import DevPorts

final class RestartTests: XCTestCase {
    // Case 21: zsh → npm → sh -c → node restarts from npm.
    func testRootClimbsThroughPackageManagerAndShC() {
        let table = [
            proc(100, parent: 50, "zsh", ["-zsh"]),
            // node's process.title renames npm's process as well as its argv.
            proc(200, parent: 100, "npm run dev", ["npm run dev"]),
            proc(300, parent: 200, "sh", ["sh", "-c", "next dev"]),
            proc(400, parent: 300, "node", ["node", "/app/node_modules/.bin/next", "dev"]),
        ]
        XCTAssertEqual(Restart.root(of: 400, in: table), 200)
    }

    // Case 22: launchd, a non-dev app or an interactive shell above it: the process is its own root.
    func testRootStopsAtLaunchdAppsAndInteractiveShells() {
        let table = [
            proc(1, parent: 0, "launchd", ["/sbin/launchd"]),
            proc(500, parent: 1, "node", ["node", "server.js"]),
            proc(600, parent: 1, "Code Helper (Plugin)", ["Code Helper (Plugin)"]),
            proc(700, parent: 600, "dart", ["dart", "tooling-daemon"]),
            proc(800, parent: 1, "zsh", ["-zsh"]),
            proc(900, parent: 800, "node", ["node", "index.js"]),
        ]
        XCTAssertEqual(Restart.root(of: 500, in: table), 500)
        XCTAssertEqual(Restart.root(of: 700, in: table), 700)
        XCTAssertEqual(Restart.root(of: 900, in: table), 900)
    }

    // Case 23: every process under the root, at any depth.
    func testDescendants() {
        let parents: [Int32: Int32] = [200: 100, 300: 200, 400: 300, 500: 100]
        XCTAssertEqual(Restart.descendants(of: 200, parents: parents), [300, 400])
    }

    // Case 24: arguments with spaces or quotes are single-quoted.
    func testQuoting() {
        XCTAssertEqual(Restart.command(argv: ["node", "/My Projects/x.js"]), "node '/My Projects/x.js'")
        XCTAssertEqual(Restart.command(argv: ["echo", "it's"]), #"echo 'it'\''s'"#)
    }

    // Case 25: a process.title argv stays raw only when it is plain words.
    func testRetitledArgv() {
        XCTAssertEqual(Restart.command(argv: ["npm run dev"]), "npm run dev")
        XCTAssertEqual(Restart.command(argv: ["npm run dev", "", ""]), "npm run dev")
        XCTAssertEqual(Restart.command(argv: ["x; rm -rf ~"]), "'x; rm -rf ~'")
    }

    private func proc(_ pid: Int32, parent: Int32, _ executable: String, _ argv: [String]) -> Restart.Proc {
        Restart.Proc(pid: pid, ppid: parent, executable: executable, argv: argv)
    }
}
