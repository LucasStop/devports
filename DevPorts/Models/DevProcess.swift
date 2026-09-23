import Foundation

struct ListeningPort: Hashable, Sendable {
    let number: Int
    let isExposed: Bool

    /// 49152–65535 is the dynamic range the OS hands out for internal IPC, not ports someone chose for a server.
    var isDynamic: Bool { number >= 49152 }
}

struct DevProcess: Identifiable, Hashable, Sendable {
    let pid: Int32
    let ppid: Int32
    let executable: String
    let argv: [String]
    let label: String
    let cwd: String?
    let project: String?
    let group: String
    let ports: [ListeningPort]
    let memoryBytes: Int64
    let startedAt: Date
    let isDev: Bool
    /// Folder of `project`, where the terminal opens and package.json lives.
    var projectPath: String? = nil

    var id: Int32 { pid }
}

enum Format {
    static func uptime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        guard minutes >= 1 else { return "<1min" }
        guard minutes >= 60 else { return "\(minutes)min" }
        let hours = minutes / 60
        guard hours >= 24 else { return "\(hours)h" }
        let (days, rest) = hours.quotientAndRemainder(dividingBy: 24)
        return rest == 0 ? "\(days)d" : "\(days)d \(rest)h"
    }

    /// Fixed pt-BR decimal comma instead of ByteCountFormatter, whose output follows the machine locale.
    static func memory(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        guard megabytes >= 1024 else { return "\(Int(megabytes.rounded())) MB" }
        return String(format: "%.1f GB", megabytes / 1024).replacingOccurrences(of: ".", with: ",")
    }
}
