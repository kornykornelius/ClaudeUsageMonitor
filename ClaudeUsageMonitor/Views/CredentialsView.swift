import SwiftUI

// MARK: - Credentials Entry
struct CredentialsView: View {
    @Binding var sessionKey: String
    @Binding var orgId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Credentials").font(.caption).bold()
            SecureField("sessionKey (sk-ant-...)", text: $sessionKey)
                .textFieldStyle(.roundedBorder)
            TextField("Organization ID", text: $orgId)
                .textFieldStyle(.roundedBorder)
        }
    }
}
