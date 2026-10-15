import Foundation

/// Processes pending snooze events, sending them to the backend with retry.
///
/// - Events are persisted in `SnoozeEventStore` so they survive app termination.
/// - On each `processQueue()` call, all pending/failed events are attempted.
/// - Exponential backoff is applied per-event based on `retryCount`.
/// - Events that succeed are marked `.sent`; events that permanently fail
///   (e.g. 4xx from backend) are marked `.failed` and not retried.
/// - The queue is driven by: app launch, network reachability changes,
///   and after each new snooze event is recorded.
@MainActor
final class SnoozeEventQueue: ObservableObject {

    static let shared = SnoozeEventQueue()

    @Published var lastPenaltyResult: PenaltyResult?

    struct PenaltyResult {
        let occurrenceId: String
        let snoozeNumber: Int
        let response: TriggerPenaltyResponse?
        let error: String?
        let capped: Bool

        var succeeded: Bool { response != nil && error == nil }
    }

    private let store: SnoozeEventStore
    private let maxRetries = 10
    private var isProcessing = false

    init(store: SnoozeEventStore = .shared) {
        self.store = store
    }

    // MARK: - Record & Send

    /// Record a new snooze event and immediately attempt to send it.
    func recordSnooze(alarmId: String, occurrenceId: String, snoozeNumber: Int) async {
        guard !store.hasEvent(occurrenceId: occurrenceId, snoozeNumber: snoozeNumber) else {
            return
        }

        let event = SnoozeEvent(
            alarmId: alarmId,
            occurrenceId: occurrenceId,
            snoozeNumber: snoozeNumber
        )
        store.append(event)
        await processQueue()
    }

    // MARK: - Queue Processing

    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let pending = store.pendingEvents()
        for event in pending {
            guard shouldRetry(event) else { continue }
            await sendEvent(event)
        }
    }

    private func shouldRetry(_ event: SnoozeEvent) -> Bool {
        guard event.retryCount < maxRetries else { return false }

        if let lastAttempt = event.lastAttempt {
            let backoff = min(pow(2.0, Double(event.retryCount)) * 2.0, 300.0)
            let nextAttempt = lastAttempt.addingTimeInterval(backoff)
            if Date() < nextAttempt { return false }
        }

        return true
    }

    private func sendEvent(_ event: SnoozeEvent) async {
        var mutableEvent = event
        mutableEvent.status = .sending
        mutableEvent.retryCount += 1
        mutableEvent.lastAttempt = Date()
        store.update(mutableEvent)

        do {
            let response = try await APIService.shared.triggerPenalty(
                alarmId: event.alarmId,
                occurrenceId: event.occurrenceId,
                snoozeNumber: event.snoozeNumber
            )

            mutableEvent.status = .sent
            store.update(mutableEvent)

            lastPenaltyResult = PenaltyResult(
                occurrenceId: event.occurrenceId,
                snoozeNumber: event.snoozeNumber,
                response: response,
                error: nil,
                capped: false
            )
        } catch let apiError as APIError {
            switch apiError {
            case .validation, .notFound, .forbidden:
                mutableEvent.status = .failed
                store.update(mutableEvent)
                lastPenaltyResult = PenaltyResult(
                    occurrenceId: event.occurrenceId,
                    snoozeNumber: event.snoozeNumber,
                    response: nil,
                    error: apiError.localizedDescription,
                    capped: false
                )
            case .unauthorized:
                await refreshTokenAndRetry(event: &mutableEvent)
            default:
                mutableEvent.status = .pending
                store.update(mutableEvent)
            }
        } catch {
            mutableEvent.status = .pending
            store.update(mutableEvent)
        }
    }

    private func refreshTokenAndRetry(event: inout SnoozeEvent) async {
        do {
            _ = try await AuthService.shared.refreshToken()
            event.status = .pending
            store.update(event)
        } catch {
            event.status = .pending
            store.update(event)
        }
    }

    // MARK: - Status

    var pendingCount: Int {
        store.pendingEvents().count
    }

    var hasPendingEvents: Bool {
        !store.pendingEvents().isEmpty
    }
}
