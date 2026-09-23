import XCTest

@testable import DevPorts

final class ProcessScannerTests: XCTestCase {
    // Cases 1–4: lsof -Fpn

    func testPortOnAllInterfacesIsExposed() {
        let ports = ProcessScanner.parseListening("p30385\nf46\nn*:8081\n")
        XCTAssertEqual(ports[30385], [ListeningPort(number: 8081, isExposed: true)])
    }

    func testLoopbackPortIsLocal() {
        let ports = ProcessScanner.parseListening("p829\nf23\nn127.0.0.1:3113\n")
        XCTAssertEqual(ports[829], [ListeningPort(number: 3113, isExposed: false)])
    }

    func testIPv6LoopbackDynamicPortIsLocalAndHiddenByDefault() throws {
        let port = try XCTUnwrap(ProcessScanner.parseListening("p35029\nf20\nn[::1]:49717\n")[35029]?.first)
        XCTAssertEqual(port, ListeningPort(number: 49717, isExposed: false))
        XCTAssertTrue(port.isDynamic)
    }

    func testSamePortOnIPv4AndIPv6IsOneEntry() {
        let output = "p658\nf10\nn*:7000\nf11\nn*:7000\nf12\nn*:5000\nf13\nn*:5000\n"
        XCTAssertEqual(
            ProcessScanner.parseListening(output)[658],
            [ListeningPort(number: 5000, isExposed: true), ListeningPort(number: 7000, isExposed: true)]
        )
    }

    // Slice 2 extra case: the kernel refuses a bind over a listener, which is how a port held by another user shows up
    // though lsof can't see it.
    func testPortIsTakenWhileSomethingListensOnIt() {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7f00_0001).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                XCTAssertEqual(Darwin.bind(listener, $0, length), 0)
                XCTAssertEqual(listen(listener, 1), 0)
                XCTAssertEqual(getsockname(listener, $0, &length), 0)
            }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))

        XCTAssertTrue(ProcessScanner.isPortTaken(port))
        close(listener)
        XCTAssertFalse(ProcessScanner.isPortTaken(port))
    }

    // Cases 5–6: ps -o pid=,ppid=,rss=,lstart=,comm=

    func testParsesPSRow() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let line = "  596 94922 812345 Mon Sep 21 12:27:45 2026 /opt/homebrew/Cellar/openjdk@17/bin/java\n"
        let row = try XCTUnwrap(ProcessScanner.parsePS(line, timeZone: utc).first)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        XCTAssertEqual(row.pid, 596)
        XCTAssertEqual(row.ppid, 94922)
        XCTAssertEqual(Format.memory(row.memoryBytes), "793 MB")
        XCTAssertEqual(
            row.startedAt,
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12, minute: 27, second: 45))
        )
        XCTAssertEqual(row.executable, "java")
    }

    func testExecutableKeepsSpacesFromComm() {
        let line =
            "91879 91440 20480 Tue Sep  1 10:00:00 2026 /Applications/Visual Studio Code.app/Contents/"
            + "Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)\n"
        XCTAssertEqual(ProcessScanner.parsePS(line).first?.executable, "Code Helper (Plugin)")
    }

    // Case 7: sysctl(KERN_PROCARGS2)

    func testProcArgsReturnsOnlyArgv() {
        let bytes = procArgs(argc: 3, execPath: "/opt/node", argv: ["node", "/p/x.js", "3000"], env: ["SECRET=abc"])
        XCTAssertEqual(ProcessScanner.parseProcArgs(bytes), ["node", "/p/x.js", "3000"])
    }

    func testTruncatedProcArgsIsNil() {
        let bytes = procArgs(argc: 3, execPath: "/opt/node", argv: ["node", "/p/x.js", "3000"], env: [])
        XCTAssertNil(ProcessScanner.parseProcArgs(Array(bytes.dropLast(3))))
        XCTAssertNil(ProcessScanner.parseProcArgs([1, 0]))
    }

    // Cases 8–12: label

    func testLabelForNodeBinUsesBinNameAndSubcommand() {
        let argv = ["node", "/Users/u/Downloads/GitHub/curitiba-bus-app/node_modules/.bin/expo", "run:ios"]
        XCTAssertEqual(ProcessScanner.label(argv: argv, executable: "node"), "expo run:ios")
    }

    func testLabelForFileInsidePackageUsesPackageName() {
        let argv = [
            "/Users/u/.nvm/versions/node/v20.19.6/bin/node",
            "/Users/u/app/node_modules/next/dist/compiled/jest-worker/processChild.js",
        ]
        XCTAssertEqual(ProcessScanner.label(argv: argv, executable: "node"), "next")
    }

    func testLabelForNpxBin() {
        let argv = ["node", "/Users/u/.npm/_npx/eea2bd7412d4593b/node_modules/.bin/context7-mcp"]
        XCTAssertEqual(ProcessScanner.label(argv: argv, executable: "node"), "context7-mcp")
    }

    func testLabelForJarDropsExtensionAndMainClass() {
        let argv = [
            "/opt/homebrew/bin/java", "-Xmx512m", "-cp",
            "/Users/u/.gradle/wrapper/dists/gradle-9.3.1-bin/abc/gradle-9.3.1/lib/gradle-daemon-main-9.3.1.jar",
            "org.gradle.launcher.daemon.bootstrap.GradleDaemon", "9.3.1",
        ]
        XCTAssertEqual(ProcessScanner.label(argv: argv, executable: "java"), "gradle-daemon-main-9.3.1")
    }

    func testLabelForSubcommandAndModule() {
        XCTAssertEqual(
            ProcessScanner.label(argv: ["/opt/homebrew/bin/dart", "tooling-daemon"], executable: "dart"),
            "tooling-daemon"
        )
        XCTAssertEqual(
            ProcessScanner.label(argv: ["python3", "-m", "http.server", "8000"], executable: "python3"),
            "http.server 8000"
        )
    }

    // Extra case 16b: node overwrites argv with process.title and blanks the remaining arguments.
    func testLabelForRetitledProcessUsesTitle() {
        XCTAssertEqual(ProcessScanner.label(argv: ["npm run dev", "", ""], executable: "node"), "npm run dev")
    }

    // Extra cases 16c–16f, from the first scan of this machine.

    func testLabelSkipsFlagValuesAndFallsBackToExecutable() {
        let argv = ["adb", "-L", "tcp:5037", "fork-server", "server", "--reply-fd", "4"]
        XCTAssertEqual(ProcessScanner.label(argv: argv, executable: "adb"), "adb")
    }

    func testLabelForGenericEntryFileUsesItsPackageFolder() {
        let argv = ["node", "/Users/u/Downloads/GitHub/_tools/clickup-mcp/build/index.js"]
        XCTAssertEqual(ProcessScanner.label(argv: argv, executable: "node"), "clickup-mcp")
    }

    func testLabelIgnoresJavaModuleFlagValues() {
        let argv = [
            "/opt/homebrew/bin/java", "--add-opens", "jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED", "-cp",
            "/Users/u/.gradle/wrapper/dists/gradle-8.14.3-bin/abc/gradle-8.14.3/lib/gradle-daemon-main-8.14.3.jar",
            "org.gradle.launcher.daemon.bootstrap.GradleDaemon",
        ]
        XCTAssertEqual(ProcessScanner.label(argv: argv, executable: "java"), "gradle-daemon-main-8.14.3")
    }

    func testGroupForFolderWithoutMarkerIsTheFolderName() {
        let home = "/Users/u"
        XCTAssertEqual(
            ProcessScanner.group(cwd: "/Users/u/Downloads/GitHub/oparceiro_geral", project: nil, home: home),
            "oparceiro_geral"
        )
        XCTAssertEqual(ProcessScanner.group(cwd: home, project: nil, home: home), "~")
    }

    // Cases 13–14: project and group

    func testProjectIsNearestFolderWithMarker() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = home.appendingPathComponent("app/src")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        FileManager.default.createFile(atPath: home.appendingPathComponent("app/package.json").path, contents: nil)

        XCTAssertEqual(ProcessScanner.projectName(cwd: source.path, home: home.path), "app")
    }

    func testGroupFallsBackToHomeFolderThenSystem() {
        let home = "/Users/u"
        XCTAssertNil(ProcessScanner.projectName(cwd: "/Users/u/.gradle/daemon/9.3.1", home: home))
        XCTAssertEqual(
            ProcessScanner.group(cwd: "/Users/u/.gradle/daemon/9.3.1", project: nil, home: home), "~/.gradle")
        XCTAssertEqual(ProcessScanner.group(cwd: "/", project: nil, home: home), "Sistema")
    }

    // Case 15: uptime

    func testUptime() {
        XCTAssertEqual(Format.uptime(45), "<1min")
        XCTAssertEqual(Format.uptime(5 * 60), "5min")
        XCTAssertEqual(Format.uptime(17 * 3600), "17h")
        XCTAssertEqual(Format.uptime((24 + 21) * 3600), "1d 21h")
    }

    // Case 16: dev classification

    func testDevExecutables() {
        XCTAssertTrue(ProcessScanner.isDevExecutable("node"))
        XCTAssertTrue(ProcessScanner.isDevExecutable("Python"))
        XCTAssertFalse(ProcessScanner.isDevExecutable("ControlCenter"))
    }

    private func procArgs(argc: Int32, execPath: String, argv: [String], env: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc.littleEndian) { Array($0) }
        bytes += Array(execPath.utf8) + [0, 0, 0, 0]
        for string in argv + env {
            bytes += Array(string.utf8) + [0]
        }
        return bytes
    }
}
