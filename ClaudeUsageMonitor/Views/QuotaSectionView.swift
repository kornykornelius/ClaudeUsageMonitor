import SwiftUI

// MARK: - Progress UI Component
struct QuotaSectionView: View {
    let quota: UsageSnapshot.Quota

    private var percentage: Int { quota.percentage.value }

    private var tint: Color {
        switch percentage {
        case 86...: .red
        case 61...: .orange
        default: .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(quota.kind.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(percentage)%")
                    .bold()
                    .monospacedDigit()
            }

            ProgressView(value: Double(percentage), total: 100)
                .tint(tint)

            HStack {
                Text("Resets:")
                Spacer()
                Text(Timestamp.short(quota.resetsAt))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }
}
