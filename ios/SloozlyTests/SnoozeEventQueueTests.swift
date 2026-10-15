import XCTest
@testable import Sloozly

final class SnoozeEventQueueTests: XCTestCase {

    private var store: SnoozeEventStore!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloozly-queue-test-\(UUID().uuidString).json")
        store = SnoozeEventStore(fileURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    // MARK: - Idempotency

    @MainActor
    func testRecordSnoozePreventsIdempotentDuplicates() async {
        let queue = SnoozeEventQueue(store: store)

        // Record the first snooze
        store.append(SnoozeEvent(
            alarmId: "a1",
            occurrenceId: "occ1",
            snoozeNumber: 1
        ))

        // Attempt to record the same snooze again
        await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)

        // Should still have only 1 event
        XCTAssertEqual(store.loadEvents().count, 1,
                       "Duplicate snooze event should not be created")
    }

    @MainActor
    func testRecordSnoozeAllowsDifferentSnoozeNumbers() async {
        let queue = SnoozeEventQueue(store: store)

        await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)
        await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 2)

        // Note: events will be marked .sending/.pending depending on API result,
        // but both should exist
        let events = store.loadEvents()
        let snoozeNumbers = Set(events.map { $0.snoozeNumber })
        XCTAssertTrue(snoozeNumbers.contains(1))
        XCTAssertTrue(snoozeNumbers.contains(2))
    }

    @MainActor
    func testRecordSnoozeAllowsDifferentOccurrences() async {
        let queue = SnoozeEventQueue(store: store)

        await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)
        await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ2", snoozeNumber: 1)

        let events = store.loadEvents()
        let occurrenceIds = Set(events.map { $0.occurrenceId })
        XCTAssertTrue(occurrenceIds.contains("occ1"))
        XCTAssertTrue(occurrenceIds.contains("occ2"))
    }

    // MARK: - Pending Count

    @MainActor
    func testPendingCountReflectsStore() {
        let queue = SnoozeEventQueue(store: store)

        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertFalse(queue.hasPendingEvents)

        store.append(SnoozeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1))
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertTrue(queue.hasPendingEvents)
    }

    @MainActor
    func testPendingCountExcludesSentEvents() {
        let queue = SnoozeEventQueue(store: store)

        var event = SnoozeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)
        event.status = .sent
        store.append(event)

        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertFalse(queue.hasPendingEvents)
    }

    // MARK: - Retry Logic

    func testRetryBackoffCalculation() {
        // This tests the concept: backoff = min(2^retryCount * 2, 300)
        let backoff0 = min(pow(2.0, 0.0) * 2.0, 300.0)
        XCTAssertEqual(backoff0, 2.0, accuracy: 0.001)

        let backoff1 = min(pow(2.0, 1.0) * 2.0, 300.0)
        XCTAssertEqual(backoff1, 4.0, accuracy: 0.001)

        let backoff5 = min(pow(2.0, 5.0) * 2.0, 300.0)
        XCTAssertEqual(backoff5, 64.0, accuracy: 0.001)

        let backoff10 = min(pow(2.0, 10.0) * 2.0, 300.0)
        XCTAssertEqual(backoff10, 300.0, accuracy: 0.001, "Should cap at 300 seconds")
    }
}
