import Foundation

// MARK: - Alarm Model

struct Alarm: Codable, Identifiable {
    let id: String
    var hour: Int
    var minute: Int
    var label: String?
    var isEnabled: Bool
    var repeatDays: [Int]
    var skipPenalty: Bool
    let createdAt: Date?
    let updatedAt: Date?
    
    // MARK: - Computed Properties
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        
        let calendar = Calendar.current
        if let date = calendar.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):\(String(format: "%02d", minute))"
    }
    
    var time24String: String {
        return "\(String(format: "%02d", hour)):\(String(format: "%02d", minute))"
    }
    
    var penaltyAmountFormatted: String {
        String(format: "$%.2f", Double(Constants.defaultPenaltyAmountCents) / 100)
    }
    
    var repeatDaysText: String {
        if repeatDays.isEmpty {
            return "One-time"
        }
        
        if repeatDays.count == 7 {
            return "Every day"
        }
        
        if repeatDays == [1, 2, 3, 4, 5] {
            return "Weekdays"
        }
        
        if repeatDays == [0, 6] {
            return "Weekends"
        }
        
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return repeatDays.sorted().map { dayNames[$0] }.joined(separator: ", ")
    }
    
    var nextAlarmDate: Date? {
        let calendar = Calendar.current
        let now = Date()
        
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        
        guard var alarmDate = calendar.date(from: components) else {
            return nil
        }
        
        // If time has passed today, move to tomorrow
        if alarmDate <= now {
            alarmDate = calendar.date(byAdding: .day, value: 1, to: alarmDate) ?? alarmDate
        }
        
        // For repeating alarms, find the next valid day
        if !repeatDays.isEmpty {
            var daysToAdd = 0
            while daysToAdd < 7 {
                let checkDate = calendar.date(byAdding: .day, value: daysToAdd, to: alarmDate) ?? alarmDate
                let weekday = calendar.component(.weekday, from: checkDate) - 1 // Convert to 0-indexed
                
                if repeatDays.contains(weekday) {
                    return checkDate
                }
                daysToAdd += 1
            }
        }
        
        return alarmDate
    }
    
    var timeUntilNextAlarm: String? {
        guard let nextDate = nextAlarmDate else { return nil }
        
        let now = Date()
        let interval = nextDate.timeIntervalSince(now)
        
        if interval < 0 { return nil }
        
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Create/Update DTOs

struct CreateAlarmRequest: Codable {
    let hour: Int
    let minute: Int
    var label: String?
    var isEnabled: Bool = true
    var repeatDays: [Int] = []
}

struct UpdateAlarmRequest: Codable {
    var hour: Int?
    var minute: Int?
    var label: String?
    var isEnabled: Bool?
    var repeatDays: [Int]?
    var skipPenalty: Bool?
}
