import Foundation

/// Generates deterministic, durable occurrence IDs for alarm firings.
///
/// Format: `{backendAlarmId}_{YYYY-MM-DD}` — one occurrence per alarm per calendar day.
/// This ensures the backend's `(occurrenceId, snoozeNumber)` idempotency works
/// correctly even if the device reboots or the app is killed between snoozes.
struct OccurrenceIDGenerator {

    /// Generate an occurrence ID for an alarm firing on a given date.
    ///
    /// The date component uses the device's current calendar and timezone so that
    /// a single night's alarm ring (e.g. 6:00 AM) maps to a single occurrence
    /// regardless of when the user actually snoozes.
    static func generate(alarmId: String, date: Date = Date()) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dateString = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return "\(alarmId)_\(dateString)"
    }

    /// Parse the alarm ID out of an occurrence ID.
    static func alarmId(from occurrenceId: String) -> String? {
        guard let range = occurrenceId.range(of: "_", options: .backwards) else {
            return nil
        }
        return String(occurrenceId[occurrenceId.startIndex..<range.lowerBound])
    }

    /// Parse the date string out of an occurrence ID.
    static func dateString(from occurrenceId: String) -> String? {
        guard let range = occurrenceId.range(of: "_", options: .backwards) else {
            return nil
        }
        return String(occurrenceId[range.upperBound...])
    }
}
