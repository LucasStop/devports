import Foundation

/// The package.json scripts of a project and the manager that runs them.
enum ProjectScripts {
    static func read(root: String) -> (manager: String, names: [String])? {
        let url = URL(fileURLWithPath: root)
        guard let data = try? Data(contentsOf: url.appendingPathComponent("package.json")),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = json["scripts"] as? [String: Any], !scripts.isEmpty
        else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return (packageManager(files: Set(files)), ordered(Array(scripts.keys)))
    }

    static func packageManager(files: Set<String>) -> String {
        if files.contains("pnpm-lock.yaml") { return "pnpm" }
        if files.contains("yarn.lock") { return "yarn" }
        if files.contains("bun.lockb") || files.contains("bun.lock") { return "bun" }
        return "npm"
    }

    /// The ones that start a server come first; they are what people open this menu for.
    static func ordered(_ names: [String]) -> [String] {
        let first = ["dev", "start"].filter(names.contains)
        return first + names.filter { !first.contains($0) }.sorted()
    }
}
