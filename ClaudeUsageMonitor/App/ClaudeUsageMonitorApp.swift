import SwiftUI

// MARK: - Main SwiftUI App Entry Point
@main
struct ClaudeUsageMonitorApp: App {
    @State private var manager = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(manager: manager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                Text(label)
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// The 5-hour session percentage is the number worth glancing at, so it is
    /// what the menu bar shows. Anything else collapses to a short word — the
    /// menu bar is not the place for an error message.
    private var label: String {
        if let fiveHour = manager.state.snapshot?.quotas.first(where: { $0.kind == .fiveHour }) {
            return "\(fiveHour.percentage.value)%"
        }
        if manager.state.error != nil {
            return "!"
        }
        return "Claude"
    }
}
