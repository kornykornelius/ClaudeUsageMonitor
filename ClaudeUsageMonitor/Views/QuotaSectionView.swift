import SwiftUI

// MARK: - Progress UI Component
struct QuotaSectionView: View {
    let title: String
    let rawUtilization: Double
    let resetTime: String

    // Convert raw API values into proper 0-100 percentage values
    var percentage: Int {
        if rawUtilization <= 1.0 {
            return Int(rawUtilization * 100)
        } else {
            return Int(min(rawUtilization, 100))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(percentage)%")
                    .bold()
            }

            ProgressView(value: Double(percentage), total: 100)
                .tint(percentage > 85 ? .red : (percentage > 60 ? .orange : .blue))

            HStack {
                Text("Resets:")
                Spacer()
                Text(resetTime)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }
}
