import Foundation
import Observation

/// The latest scan. Refreshed every 5 s while the popover is open and every 30 s while it is closed, when only the
/// menu bar counter needs it.
@Observable @MainActor
final class Store {
    private(set) var processes: [DevProcess] = []
    @ObservationIgnored private var polling: Task<Void, Never>?

    init() { setPopoverOpen(false) }

    var devPortCount: Int { Overview(processes: processes).ports.count }

    /// Restarts polling with a scan right away, so opening the popover never shows data 30 s old.
    func setPopoverOpen(_ isOpen: Bool) {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(isOpen ? 5 : 30))
            }
        }
    }

    func refresh() async {
        processes = await Task.detached(priority: .userInitiated) { ProcessScanner.scan() }.value
    }
}
