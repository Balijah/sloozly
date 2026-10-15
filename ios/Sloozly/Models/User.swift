import Foundation

// MARK: - User Model

struct User: Codable, Identifiable {
    let id: String
    let email: String
    var displayName: String?
    var timezone: String
    let createdAt: Date
    var bankAccount: BankAccountInfo?
    var counts: UserCounts?
    
    struct UserCounts: Codable {
        let alarms: Int
        let penalties: Int
    }
}

// MARK: - Bank Account Info (subset for display)

struct BankAccountInfo: Codable, Identifiable {
    let id: String
    let institutionName: String
    let accountName: String
    let accountMask: String
    let status: BankAccountStatus
}

enum BankAccountStatus: String, Codable {
    case active = "ACTIVE"
    case needsRelink = "NEEDS_RELINK"
    case disabled = "DISABLED"
    
    var displayText: String {
        switch self {
        case .active:
            return "Connected"
        case .needsRelink:
            return "Needs Reconnection"
        case .disabled:
            return "Disabled"
        }
    }
    
    var isHealthy: Bool {
        self == .active
    }
}
