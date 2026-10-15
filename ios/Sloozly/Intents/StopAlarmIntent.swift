import AlarmKit
import AppIntents
import Foundation

/// App Intent executed when the user taps "I'm Up!" on the AlarmKit alert.
///
/// This stops the alarm and resets the snooze state for the current occurrence.
public struct StopAlarmIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Stop Alarm"
    public static let description = IntentDescription("Stops the alarm")

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

    public func perform() async throws -> some IntentResult {
        // Process any remaining pending snooze events
        await SnoozeEventQueue.shared.processQueue()
        return .result()
    }
}
