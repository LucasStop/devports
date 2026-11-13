import Foundation

enum PopoverTab: String, CaseIterable {
    case ports = "Portas"
    case apps = "Apps"
    case terminal = "Terminal"
}

/// Width and height of the popover for one tab. A nil height grows with the content, up to 660 pt.
struct PanelSize: Codable, Equatable {
    var width = 440.0
    var height: Double?
}

/// The Ajustes choice: one size for every tab, or one per tab. Stored as JSON under one `@AppStorage` key.
struct PopoverSizes: Codable, Equatable, RawRepresentable {
    static let widthRange = 360.0...720.0
    static let heightRange = 300.0...660.0
    static let defaultFixedHeight = 420.0

    var same = true
    var all = PanelSize()
    var ports = PanelSize()
    var apps = PanelSize()
    var terminal = PanelSize()

    init() {}

    // Field-wise: RawRepresentable's default == would compare the JSON strings.
    static func == (a: Self, b: Self) -> Bool {
        a.same == b.same && a.all == b.all && a.ports == b.ports && a.apps == b.apps && a.terminal == b.terminal
    }

    // Explicit: RawRepresentable's default Codable would encode a bare string and recurse through `rawValue`.
    private enum CodingKeys: String, CodingKey { case same, all, ports, apps, terminal }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        same = try c.decode(Bool.self, forKey: .same)
        all = try c.decode(PanelSize.self, forKey: .all)
        ports = try c.decode(PanelSize.self, forKey: .ports)
        apps = try c.decode(PanelSize.self, forKey: .apps)
        terminal = try c.decode(PanelSize.self, forKey: .terminal)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(same, forKey: .same)
        try c.encode(all, forKey: .all)
        try c.encode(ports, forKey: .ports)
        try c.encode(apps, forKey: .apps)
        try c.encode(terminal, forKey: .terminal)
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = value
    }

    var rawValue: String {
        // Sorted keys keep the string stable, so equal values give equal raw values.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// With the Terminal opening in a window, its tab only shows a notice, so its size does not apply.
    func size(for tab: PopoverTab, terminalHost: TerminalSessions.Host) -> PanelSize {
        let size =
            switch tab {
            case _ where same: all
            case .ports: ports
            case .apps: apps
            case .terminal: terminal
            }
        if tab == .terminal && !same && terminalHost == .window { return PanelSize() }
        return PanelSize(
            width: size.width.clamped(to: Self.widthRange),
            height: size.height.map { $0.clamped(to: Self.heightRange) })
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
