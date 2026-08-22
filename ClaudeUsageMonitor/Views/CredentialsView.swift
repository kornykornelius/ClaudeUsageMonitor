import SwiftUI

// MARK: - Credentials Entry
struct CredentialsView: View {
    @Binding var sessionKey: String
    @Binding var cfClearance: String
    @Binding var orgId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Credentials").font(.caption).bold()

            SecureField("sessionKey (sk-ant-...)", text: $sessionKey)
                .textFieldStyle(.roundedBorder)

            TextField("Organization ID", text: $orgId)
                .textFieldStyle(.roundedBorder)

            SecureField("cf_clearance (optional)", text: $cfClearance)
                .textFieldStyle(.roundedBorder)

            Text("cf_clearance is only needed when Cloudflare is challenging requests.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
