import AlarmKit
import AppIntents
import Foundation

/// App Intent executed when the user taps "Snooze" on the AlarmKit alert.
///
/// This records the snooze event locally and queues a penalty API call.
/// The alarm's `secondaryButtonBehavior: .countdown` handles restarting the
/// countdown automatically; this intent handles the business logic.
public struct SnoozeAlarmIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Snooze Alarm"
    public static let description = IntentDescription("Snoozes the alarm and records a penalty")

    @Parameter(title: "Alarm ID")
    public var alarmID: String

    @Parameter(title: "Backend Alarm ID")
    public var backendAlarmID: String

    public init(alarmID: String, backendAlarmID: String) {
        self.alarmID = alarmID
        self.backendAlarmID = backendAlarmID
    }

    public init() {
        self.alarmID = ""
        self.backendAlarmID = ""
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let occurrenceId = OccurrenceIDGenerator.generate(alarmId: backendAlarmID)
        let store = SnoozeEventStore.shared
        let snoozeNumber = store.snoozeCount(for: occurrenceId) + 1

        await SnoozeEventQueue.shared.recordSnooze(
            alarmId: backendAlarmID,
            occurrenceId: occurrenceId,
            snoozeNumber: snoozeNumber
        )

        return .result()
    }
}
