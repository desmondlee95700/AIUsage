import Foundation
import SwiftUI
import Combine

public class QuotaService: ObservableObject {
    public static let shared = QuotaService()
    
    @Published public var isConnected: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var lastUpdated: Date? = nil
    @Published public var discoveredServer: DiscoveredServer? = nil
    
    @Published public var quotaSummary: QuotaSummaryData? = nil
    @Published public var userStatus: UserStatusData? = nil
    
    // User preferences
    @Published public var displayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "menuBarDisplayMode")
            updateMenuBarCallback?()
        }
    }
    
    @Published public var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval")
            restartTimer()
        }
    }
    
    public var updateMenuBarCallback: (() -> Void)?
    
    private var timer: Timer?
    private let session: URLSession
    
    public init() {
        let savedMode = UserDefaults.standard.string(forKey: "menuBarDisplayMode")
        self.displayMode = MenuBarDisplayMode(rawValue: savedMode ?? "") ?? .weekly
        
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshInterval")
        self.refreshInterval = RefreshInterval(rawValue: savedInterval == 0 ? 60 : savedInterval) ?? .oneMinute
        
        self.session = URLSession(configuration: .ephemeral, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
        
        restartTimer()
    }
    
    public func restartTimer() {
        timer?.invalidate()
        timer = nil
        
        guard refreshInterval.rawValue > 0 else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval.rawValue), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    public func refresh(forceDiscovery: Bool = false) {
        guard !isLoading else { return }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            guard let server = ProcessDiscovery.discover(forceRefresh: forceDiscovery) else {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.discoveredServer = nil
                    self.isLoading = false
                    self.errorMessage = "Antigravity is not running. Please launch Antigravity to view model usage."
                    self.updateMenuBarCallback?()
                }
                return
            }
            
            let group = DispatchGroup()
            var fetchedQuota: QuotaSummaryData?
            var fetchedStatus: UserStatusData?
            var quotaError: Error?
            
            // 1. Fetch Quota Summary
            group.enter()
            self.fetchQuotaSummary(server: server) { result in
                switch result {
                case .success(let data):
                    fetchedQuota = data
                case .failure(let err):
                    quotaError = err
                }
                group.leave()
            }
            
            // 2. Fetch User Status
            group.enter()
            self.fetchUserStatus(server: server) { result in
                switch result {
                case .success(let data):
                    fetchedStatus = data
                case .failure:
                    break
                }
                group.leave()
            }
            
            group.notify(queue: .main) {
                self.isLoading = false
                if let quota = fetchedQuota {
                    self.isConnected = true
                    self.discoveredServer = server
                    self.quotaSummary = quota
                    self.userStatus = fetchedStatus
                    self.lastUpdated = Date()
                    self.errorMessage = nil
                } else {
                    self.isConnected = false
                    self.errorMessage = quotaError?.localizedDescription ?? "Failed to fetch model quota from Antigravity."
                }
                self.updateMenuBarCallback?()
            }
        }
    }
    
    private func fetchQuotaSummary(server: DiscoveredServer, completion: @escaping (Result<QuotaSummaryData, Error>) -> Void) {
        guard let url = URL(string: "https://127.0.0.1:\(server.port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(server.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 5.0
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(URLError(.zeroByteResource)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(QuotaSummaryResponse.self, from: data)
                if let quotaData = decoded.response {
                    completion(.success(quotaData))
                } else {
                    completion(.failure(URLError(.cannotParseResponse)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func fetchUserStatus(server: DiscoveredServer, completion: @escaping (Result<UserStatusData, Error>) -> Void) {
        guard let url = URL(string: "https://127.0.0.1:\(server.port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(server.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 5.0
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(URLError(.zeroByteResource)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(UserStatusResponse.self, from: data)
                if let status = decoded.userStatus {
                    completion(.success(status))
                } else {
                    completion(.failure(URLError(.cannotParseResponse)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Menu Bar Formatter Helpers
    
    public var primaryWeeklyBucket: QuotaBucket? {
        guard let groups = quotaSummary?.groups else { return nil }
        let group = groups.first { $0.displayName.contains("Gemini") } ?? groups.first
        return group?.buckets.first { $0.window == "weekly" || $0.bucketId.contains("weekly") }
    }
    
    public var primary5hBucket: QuotaBucket? {
        guard let groups = quotaSummary?.groups else { return nil }
        let group = groups.first { $0.displayName.contains("Gemini") } ?? groups.first
        return group?.buckets.first { $0.window == "5h" || $0.bucketId.contains("5h") }
    }
    
    public var menuBarTitle: String {
        guard isConnected else {
            return " Antigravity Offline"
        }
        
        let weeklyPct = primaryWeeklyBucket?.percentage ?? 0
        let fiveHPct = primary5hBucket?.percentage ?? 100
        
        switch displayMode {
        case .iconOnly:
            return ""
        case .weekly:
            return " \(weeklyPct)%"
        case .weeklyAnd5h:
            return " \(weeklyPct)% · \(fiveHPct)%"
        }
    }
    
    public var statusTintColor: NSColor {
        guard isConnected, let weeklyPct = primaryWeeklyBucket?.percentage else {
            return .secondaryLabelColor
        }
        
        if weeklyPct >= 50 {
            return NSColor(red: 0.13, green: 0.77, blue: 0.36, alpha: 1.0) // Green #22c55e
        } else if weeklyPct >= 20 {
            return NSColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0) // Orange #f59e0b
        } else {
            return NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0) // Red #ef4444
        }
    }
}
