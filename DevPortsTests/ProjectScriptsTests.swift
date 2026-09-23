import XCTest

@testable import DevPorts

final class ProjectScriptsTests: XCTestCase {
    // Case 19: the lockfile picks the package manager.
    func testLockfilePicksPackageManager() {
        XCTAssertEqual(ProjectScripts.packageManager(files: ["package.json", "pnpm-lock.yaml"]), "pnpm")
        XCTAssertEqual(ProjectScripts.packageManager(files: ["yarn.lock"]), "yarn")
        XCTAssertEqual(ProjectScripts.packageManager(files: ["bun.lockb"]), "bun")
        XCTAssertEqual(ProjectScripts.packageManager(files: ["bun.lock"]), "bun")
        XCTAssertEqual(ProjectScripts.packageManager(files: ["package.json"]), "npm")
    }

    // Case 20: dev and start first, the rest alphabetically.
    func testScriptOrder() {
        XCTAssertEqual(
            ProjectScripts.ordered(["build", "test", "dev", "lint", "start"]),
            ["dev", "start", "build", "lint", "test"])
    }

    func testReadsScriptsFromPackageJSON() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"scripts":{"build":"next build","dev":"next dev"}}"#.utf8)
            .write(to: root.appendingPathComponent("package.json"))
        FileManager.default.createFile(atPath: root.appendingPathComponent("yarn.lock").path, contents: nil)

        let scripts = try XCTUnwrap(ProjectScripts.read(root: root.path))
        XCTAssertEqual(scripts.manager, "yarn")
        XCTAssertEqual(scripts.names, ["dev", "build"])
    }
}
