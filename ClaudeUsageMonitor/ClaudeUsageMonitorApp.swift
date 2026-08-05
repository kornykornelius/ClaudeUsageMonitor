import SwiftUI
import Combine

// MARK: - API Response Models
struct UsageResponse: Codable {
    let fiveHour: LimitDetail?
    let sevenDay: LimitDetail?
    let sevenDaySonnet: LimitDetail?
    let sevenDayOpus: LimitDetail?
    let extraUsage: ExtraUsageDetail?
    
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
    }
}

struct LimitDetail: Codable {
    let utilization: Double // API value (0.0 to 1.0 or 0 to 100)
    let resetsAt: String?   // ISO timestamp
    
    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
    
    var formattedResetTime: String {
        guard let resetsAt = resetsAt else { return "N/A" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        displayFormatter.timeStyle = .short
        
        if let date = formatter.date(from: resetsAt) ?? ISO8601DateFormatter().date(from: resetsAt) {
            return displayFormatter.string(from: date)
        }
        return resetsAt
    }
}

struct ExtraUsageDetail: Codable {
    let isAvailable: Bool?
    let currentBalance: Double?
    let monthlyLimit: Double?
    let expiresAt: String?
    
    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case currentBalance = "current_balance"
        case monthlyLimit = "monthly_limit"
        case expiresAt = "expires_at"
    }
    
    var formattedExpiration: String {
        guard let expiresAt = expiresAt else { return "N/A" }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: expiresAt) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return expiresAt
    }
}

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

// MARK: - Main SwiftUI App Entry Point
@main
struct ClaudeUsageMonitorApp: App {
    @StateObject private var manager = ClaudeUsageManager()
    
    var body: some Scene {
        MenuBarExtra {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    
                    // Header
                    HStack {
                        Image(systemName: "brain.head.profile")
                        Text("Claude Usage Dashboard")
                            .font(.headline)
                        Spacer()
                        if manager.isLoading {
                            ProgressView().controlSize(.small)
                        }
                    }
                    
                    Divider()
                    
                    if let usage = manager.usageData {
                        
                        // 1. Current 5-Hour Session Window
                        if let fiveHour = usage.fiveHour {
                            QuotaSectionView(
                                title: "Current 5-Hour Session",
                                rawUtilization: fiveHour.utilization,
                                resetTime: fiveHour.formattedResetTime
                            )
                        }
                        
                        Divider()
                        
                        // 2. Weekly Quotas (7-Day Limits)
                        Text("Weekly Quotas (7-Day Limits)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        if let sevenDay = usage.sevenDay {
                            QuotaSectionView(
                                title: "All Models Total",
                                rawUtilization: sevenDay.utilization,
                                resetTime: sevenDay.formattedResetTime
                            )
                        }
                        
                        if let sonnet = usage.sevenDaySonnet {
                            QuotaSectionView(
                                title: "Sonnet Specific",
                                rawUtilization: sonnet.utilization,
                                resetTime: sonnet.formattedResetTime
                            )
                        }
                        
                        if let opus = usage.sevenDayOpus {
                            QuotaSectionView(
                                title: "Opus Specific",
                                rawUtilization: opus.utilization,
                                resetTime: opus.formattedResetTime
                            )
                        }
                        
                        Divider()
                        
                        // 3. Usage Credits & Monthly Limits
                        if let credit = usage.extraUsage, credit.isAvailable == true {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Extra Usage Credits")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Text("Current Balance:")
                                    Spacer()
                                    Text("$\(credit.currentBalance ?? 0.0, specifier: "%.2f")")
                                        .bold()
                                }
                                .font(.subheadline)
                                
                                HStack {
                                    Text("Monthly Spend Cap:")
                                    Spacer()
                                    Text("$\(credit.monthlyLimit ?? 0.0, specifier: "%.2f")")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                
                                HStack {
                                    Text("Expires:")
                                    Spacer()
                                    Text(credit.formattedExpiration)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        
                    } else {
                        Text(manager.statusText)
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    
                    Divider()
                    
                    // Configuration Settings
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Credentials").font(.caption).bold()
                        SecureField("sessionKey (sk-ant-...)", text: $manager.sessionKey)
                            .textFieldStyle(.roundedBorder)
                        TextField("Organization ID", text: $manager.orgId)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Button("Refresh") {
                            Task { await manager.fetchUsage() }
                        }
                        Spacer()
                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
                .padding(12)
            }
            .frame(width: 300, height: 460)
            .onAppear {
                Task { await manager.fetchUsage() }
            }
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
