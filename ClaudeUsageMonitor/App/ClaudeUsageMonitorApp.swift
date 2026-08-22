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
                if let fiveHour = manager.usageData?.fiveHour {
                    let val = fiveHour.utilization
                    let pct = val <= 1.0 ? Int(val * 100) : Int(min(val, 100))
                    Text("\(pct)%")
                } else {
                    Text("Claude")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
