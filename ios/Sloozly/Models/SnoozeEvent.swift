import Foundation

struct SnoozeEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let alarmId: String
    let occurrenceId: String
    let snoozeNumber: Int
    let timestamp: Date
    var status: SendStatus

    enum SendStatus: String, Codable {
        case pending
        case sending
        case sent
        case failed
    }

    var retryCount: Int
    var lastAttempt: Date?

    init(
        alarmId: String,
        occurrenceId: String,
        snoozeNumber: Int,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.alarmId = alarmId
        self.occurrenceId = occurrenceId
        self.snoozeNumber = snoozeNumber
        self.timestamp = timestamp
        self.status = .pending
        self.retryCount = 0
        self.lastAttempt = nil
    }
}
