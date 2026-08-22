import SwiftUI
import Combine

// MARK: - View Model Manager
@MainActor
class ClaudeUsageManager: ObservableObject {
    @Published var usageData: UsageResponse?
    @Published var statusText: String = "Loading..."
    @Published var isLoading: Bool = false

    @AppStorage("sessionKey") var sessionKey: String = ""
    @AppStorage("orgId") var orgId: String = ""

    private var timer: Timer?

    init() {
        startTimer()
    }

    func startTimer() {
        timer?.invalidate()
        // Automatically fetches updates every 3 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { _ in
            Task { await self.fetchUsage() }
        }
    }

    func fetchUsage() async {
        guard !sessionKey.isEmpty, !orgId.isEmpty else {
            self.statusText = "Setup Required"
            return
        }

        let cleanKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOrg = orgId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: "https://claude.ai/api/organizations/\(cleanOrg)/usage") else {
            self.statusText = "Invalid URL / Org ID"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        // Full browser headers to pass Cloudflare checks
        request.setValue("sessionKey=\(cleanKey)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")

        self.isLoading = true

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            self.isLoading = false

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    self.usageData = try decoder.decode(UsageResponse.self, from: data)
                    self.statusText = "Updated"
                } else {
                    self.statusText = "HTTP Error \(httpResponse.statusCode) (Check Credentials)"
                }
            }
        } catch {
            self.isLoading = false
            self.statusText = "Network Error: \(error.localizedDescription)"
        }
    }
}
