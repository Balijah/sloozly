import Foundation

// MARK: - Penalty Model

struct Penalty: Codable, Identifiable {
    let id: String
    let amount: Int // In cents
    let snoozeNumber: Int
    let status: PenaltyStatus
    let failureReason: String?
    let triggeredAt: Date
    let processedAt: Date?
    let alarm: AlarmSummary?
    
    struct AlarmSummary: Codable {
        let id: String
        let label: String?
        let hour: Int
        let minute: Int
    }
    
    // MARK: - Computed Properties
    
    var amountFormatted: String {
        return String(format: "$%.2f", Double(amount) / 100.0)
    }
    
    var alarmTimeString: String? {
        guard let alarm = alarm else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        var components = DateComponents()
        components.hour = alarm.hour
        components.minute = alarm.minute
        
        let calendar = Calendar.current
        if let date = calendar.date(from: components) {
            return formatter.string(from: date)
        }
        return nil
    }
    
    var displayTitle: String {
        if let label = alarm?.label, !label.isEmpty {
            return label
        }
        return alarmTimeString ?? "Alarm"
    }
    
    var triggeredAtFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: triggeredAt)
    }
}

enum PenaltyStatus: String, Codable {
    case pending = "PENDING"
    case processing = "PROCESSING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    
    var displayText: String {
        switch self {
        case .pending:
            return "Pending"
        case .processing:
            return "Processing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
    
    var iconName: String {
        switch self {
        case .pending:
            return "clock"
        case .processing:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .pending:
            return "orange"
        case .processing:
            return "blue"
        case .completed:
            return "green"
        case .failed:
            return "red"
        }
    }
}

// MARK: - Penalty Stats

struct PenaltyStats: Codable {
    let lifetime: LifetimeStats
    let byStatus: [String: StatusStats]
    let last7Days: Last7DaysStats
    
    struct LifetimeStats: Codable {
        let totalAmount: Int
        let totalAmountFormatted: String
        let totalPenalties: Int
        let averageAmount: Int
        let averageAmountFormatted: String
    }
    
    struct StatusStats: Codable {
        let count: Int
        let amount: Int
        let amountFormatted: String
    }
    
    struct Last7DaysStats: Codable {
        let count: Int
        let amount: Int
        let amountFormatted: String
    }
}

// MARK: - Trigger Penalty Request

struct TriggerPenaltyRequest: Codable {
    let alarmId: String
    let occurrenceId: String
    let snoozeNumber: Int
}

struct TriggerPenaltyResponse: Codable {
    let penaltyId: String
    let amount: Int
    let amountFormatted: String
    let snoozeNumber: Int
    let status: PenaltyStatus
    let triggeredAt: Date
}
