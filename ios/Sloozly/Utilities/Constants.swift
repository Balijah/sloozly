import Foundation

// MARK: - Environment Configuration

enum Environment {
    static var current: EnvironmentType {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
    
    enum EnvironmentType {
        case development
        case production
        
        var apiBaseURL: String {
            switch self {
            case .development:
                return "http://localhost:3000/api"
            case .production:
                return "https://api.sloozly.com/api"
            }
        }
        
        var plaidEnv: String {
            switch self {
            case .development:
                return "sandbox"
            case .production:
                return "production"
            }
        }
    }
}

// MARK: - App Constants

enum Constants {
    // API
    static let apiBaseURL = Environment.current.apiBaseURL
    static let apiTimeout: TimeInterval = 30
    
    // Plaid
    static let plaidEnv = Environment.current.plaidEnv
    
    // Alarm
    static let defaultPenaltyAmountCents = 500 // $5.00
    static let maxPenaltyAmountCents = 5000 // $50.00
    static let maxSnoozeCount = 20
    static let defaultSnoozeDurationMinutes = 9
    
    // Keychain Keys
    enum KeychainKeys {
        static let authToken = "com.sloozly.authToken"
        static let userId = "com.sloozly.userId"
    }
    
    // UserDefaults Keys
    enum UserDefaultsKeys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastAlarmId = "lastAlarmId"
        static let snoozeCount = "snoozeCount"
    }
    
    // Notification Identifiers
    enum NotificationIdentifiers {
        static let alarmCategory = "ALARM_CATEGORY"
        static let snoozeAction = "SNOOZE_ACTION"
        static let dismissAction = "DISMISS_ACTION"
    }
}

// MARK: - Day of Week

enum DayOfWeek: Int, CaseIterable {
    case sunday = 0
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    
    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }
    
    var initial: String {
        switch self {
        case .sunday: return "S"
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        }
    }
    
    static var weekdays: [DayOfWeek] {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }
    
    static var weekends: [DayOfWeek] {
        [.saturday, .sunday]
    }
}
