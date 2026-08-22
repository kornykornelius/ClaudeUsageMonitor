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

            QuotaBar(fraction: Double(percentage) / 100, tint: tint)

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

/// A fixed-height utilisation bar.
///
/// Drawn from primitives rather than using `ProgressView(value:)` so the fill
/// colour is exactly the one chosen here — the stock control's tint is
/// influenced by the system accent and control style — and so the bar appears
/// in offscreen snapshots, which `ProgressView` does not survive.
struct QuotaBar: View {
    /// 0...1.
    let fraction: Double
    let tint: Color

    private static let height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: Self.height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Utilisation")
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}
