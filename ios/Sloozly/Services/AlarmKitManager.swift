import AlarmKit
import Foundation
import SwiftUI

/// Manages all AlarmKit interactions for Sloozly.
///
/// Responsibilities:
/// - Request and observe AlarmKit authorization
/// - Schedule / cancel / snooze alarms via `AlarmManager`
/// - Observe `alarmUpdates` for UI state; only the snooze intent records penalties
@MainActor
final class AlarmKitManager: ObservableObject {

    static let shared = AlarmKitManager()

    @Published var authorizationState: AlarmManager.AuthorizationState = .notDetermined
    @Published var currentAlarmState: Alarm.State?
    @Published var isAlarmScheduled = false

    private var observationTask: Task<Void, Never>?
    private var authObservationTask: Task<Void, Never>?

    private var activeAlarmUUID: UUID?

    private init() {
        self.authorizationState = AlarmManager.shared.authorizationState
    }

    // MARK: - Authorization

    func requestAuthorization() async -> AlarmManager.AuthorizationState {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            self.authorizationState = state
            return state
        } catch {
            return .denied
        }
    }

    func checkAuthorization() {
        self.authorizationState = AlarmManager.shared.authorizationState
    }

    func startAuthorizationObservation() {
        authObservationTask?.cancel()
        authObservationTask = Task { [weak self] in
            for await state in AlarmManager.shared.authorizationUpdates {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.authorizationState = state
                }
            }
        }
    }

    // MARK: - Schedule Alarm

    /// Schedule a wake-up alarm using AlarmKit.
    ///
    /// - Parameters:
    ///   - alarm: The backend alarm model (contains hour, minute, repeatDays, label).
    /// - Returns: `true` if scheduling succeeded.
    @discardableResult
    func scheduleAlarm(_ alarm: AlarmModel) async -> Bool {
        if authorizationState != .authorized {
            let state = await requestAuthorization()
            guard state == .authorized else { return false }
        }

        let alarmUUID = stableUUID(for: alarm.id)

        let schedule: Alarm.Schedule
        if alarm.repeatDays.isEmpty {
            if let nextDate = alarm.nextAlarmDate {
                schedule = .fixed(nextDate)
            } else {
                return false
            }
        } else {
            let weekdays = alarm.repeatDays.compactMap { dayIndexToWeekday($0) }
            let time = Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
            let recurrence: Alarm.Schedule.Relative.Recurrence
            if weekdays.isEmpty {
                recurrence = .never
            } else {
                recurrence = .weekly(weekdays)
            }
            let relative = Alarm.Schedule.Relative(time: time, repeats: recurrence)
            schedule = .relative(relative)
        }

        let stopButton = AlarmButton(
            text: "I'm Up!",
            textColor: .white,
            systemImageName: "sun.max.fill"
        )

        let snoozeButton = AlarmButton(
            text: "Snooze ($\(String(format: "%.2f", Double(Constants.defaultPenaltyAmountCents) / 100.0)))",
            textColor: .white,
            systemImageName: "zzz"
        )

        let title = alarm.label ?? "Time to Wake Up!"

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let countdownPresentation = AlarmPresentation.Countdown(
            title: "Snooze — \(title)"
        )

        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )

        let metadata = SloozlyAlarmMetadata(
            backendAlarmId: alarm.id,
            label: alarm.label
        )

        let attributes = AlarmAttributes<SloozlyAlarmMetadata>(
            presentation: presentation,
            metadata: metadata,
            tintColor: Color.orange
        )

        let snoozeDuration = TimeInterval(Constants.defaultSnoozeDurationMinutes * 60)
        let countdownDuration = Alarm.CountdownDuration(
            preAlert: nil,
            postAlert: snoozeDuration
        )

        let snoozeIntent = SnoozeAlarmIntent(
            alarmID: alarmUUID.uuidString,
            backendAlarmID: alarm.id
        )

        let stopIntent = StopAlarmIntent(
            alarmID: alarmUUID.uuidString,
            backendAlarmID: alarm.id
        )

        let configuration = AlarmManager.AlarmConfiguration<SloozlyAlarmMetadata>(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: snoozeIntent,
            sound: .default
        )

        do {
            _ = try await AlarmManager.shared.schedule(
                id: alarmUUID,
                configuration: configuration
            )
            activeAlarmUUID = alarmUUID
            isAlarmScheduled = true
            startAlarmObservation()
            return true
        } catch {
            print("Failed to schedule AlarmKit alarm: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Cancel Alarm

    func cancelAlarm(_ alarm: AlarmModel) async {
        let alarmUUID = stableUUID(for: alarm.id)
        do {
            try AlarmManager.shared.cancel(id: alarmUUID)
        } catch {
            print("Failed to cancel AlarmKit alarm: \(error.localizedDescription)")
        }
        if activeAlarmUUID == alarmUUID {
            activeAlarmUUID = nil
            isAlarmScheduled = false
            currentAlarmState = nil
        }
    }

    // MARK: - Alarm State Observation

    func startAlarmObservation() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard !Task.isCancelled else { return }
                await self?.handleAlarmUpdates(alarms)
            }
        }
    }

    private func handleAlarmUpdates(_ alarms: [AlarmKit.Alarm]) async {
        guard let uuid = activeAlarmUUID else { return }

        guard let alarm = alarms.first(where: { $0.id == uuid }) else {
            currentAlarmState = nil
            return
        }

        currentAlarmState = alarm.state
    }

    // MARK: - Helpers

    /// Derive a stable UUID from a backend alarm ID string.
    /// Uses UUID v5 (name-based) with a fixed Sloozly namespace so the
    /// same backend alarm ID always produces the same AlarmKit alarm ID.
    func stableUUID(for backendAlarmId: String) -> UUID {
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")! // DNS namespace
        let name = "sloozly.alarm.\(backendAlarmId)"
        return UUID.v5(namespace: namespace, name: name)
    }

    private func dayIndexToWeekday(_ index: Int) -> Locale.Weekday? {
        switch index {
        case 0: return .sunday
        case 1: return .monday
        case 2: return .tuesday
        case 3: return .wednesday
        case 4: return .thursday
        case 5: return .friday
        case 6: return .saturday
        default: return nil
        }
    }

    // MARK: - Cleanup

    func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
        authObservationTask?.cancel()
        authObservationTask = nil
    }
}

// MARK: - UUID v5 (SHA-1 name-based)

extension UUID {
    /// Generate a v5 UUID from a namespace UUID and a name string.
    static func v5(namespace: UUID, name: String) -> UUID {
        let namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        let nameBytes = [UInt8](name.utf8)

        var input = namespaceBytes
        input.append(contentsOf: nameBytes)

        // SHA-1 hash (using CommonCrypto via CC_SHA1 or a simple implementation)
        let hash = sha1(input)

        // Build UUID from first 16 bytes of SHA-1 hash
        var uuidBytes = Array(hash.prefix(16))
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50  // version 5
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80  // variant 1

        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    /// Minimal SHA-1 implementation (no CommonCrypto dependency).
    private static func sha1(_ data: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        let ml = UInt64(data.count * 8)
        var msg = data
        msg.append(0x80)
        while msg.count % 64 != 56 {
            msg.append(0x00)
        }
        for i in stride(from: 56, through: 0, by: -8) {
            msg.append(UInt8(truncatingIfNeeded: ml >> i))
        }

        for chunkStart in stride(from: 0, to: msg.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                w[i] = UInt32(msg[offset]) << 24
                    | UInt32(msg[offset + 1]) << 16
                    | UInt32(msg[offset + 2]) << 8
                    | UInt32(msg[offset + 3])
            }
            for i in 16..<80 {
                w[i] = (w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]).rotatedLeft(by: 1)
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4

            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temp = a.rotatedLeft(by: 5) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = b.rotatedLeft(by: 30); b = a; a = temp
            }

            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d; h4 = h4 &+ e
        }

        var result = [UInt8]()
        for h in [h0, h1, h2, h3, h4] {
            result.append(UInt8(truncatingIfNeeded: h >> 24))
            result.append(UInt8(truncatingIfNeeded: h >> 16))
            result.append(UInt8(truncatingIfNeeded: h >> 8))
            result.append(UInt8(truncatingIfNeeded: h))
        }
        return result
    }
}

private extension UInt32 {
    func rotatedLeft(by amount: UInt32) -> UInt32 {
        (self << amount) | (self >> (32 - amount))
    }
}
