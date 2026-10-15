import XCTest
@testable import Sloozly

final class SnoozeEventStoreTests: XCTestCase {

    private var store: SnoozeEventStore!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloozly-test-\(UUID().uuidString).json")
        store = SnoozeEventStore(fileURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testInterruptedSendIsRetriedAfterReload() {
        var event = makeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)
        event.status = .sending
        store.append(event)
        XCTAssertTrue(store.pendingEvents().isEmpty, "Do not retry an active request")
        let restarted = SnoozeEventStore(fileURL: tempURL)
        XCTAssertEqual(restarted.pendingEvents().map(\.id), [event.id])
        XCTAssertEqual(restarted.snoozeCount(for: "occ1"), 1)
    }

    // MARK: - Basic CRUD

    func testEmptyStoreReturnsNoEvents() {
        XCTAssertTrue(store.loadEvents().isEmpty)
    }

    func testAppendAndLoad() {
        let event = makeEvent(alarmId: "a1", occurrenceId: "a1_2026-01-01", snoozeNumber: 1)
        store.append(event)

        let events = store.loadEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].alarmId, "a1")
        XCTAssertEqual(events[0].snoozeNumber, 1)
    }

    func testMultipleAppends() {
        store.append(makeEvent(alarmId: "a1", occurrenceId: "a1_2026-01-01", snoozeNumber: 1))
        store.append(makeEvent(alarmId: "a1", occurrenceId: "a1_2026-01-01", snoozeNumber: 2))
        store.append(makeEvent(alarmId: "a1", occurrenceId: "a1_2026-01-01", snoozeNumber: 3))

        XCTAssertEqual(store.loadEvents().count, 3)
    }

    func testUpdateEvent() {
        var event = makeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)
        store.append(event)

        event.status = .sent
        store.update(event)

        let loaded = store.loadEvents()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].status, .sent)
    }

    func testClearAll() {
        store.append(makeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1))
        store.append(makeEvent(alarmId: "a2", occurrenceId: "occ2", snoozeNumber: 1))
        XCTAssertEqual(store.loadEvents().count, 2)

        store.clearAll()
        XCTAssertTrue(store.loadEvents().isEmpty)
    }

    // MARK: - Queries

    func testPendingEvents() {
        var sent = makeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)
        sent.status = .sent
        store.append(sent)

        let pending = makeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 2)
        store.append(pending)

        var failed = makeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 3)
        failed.status = .failed
        store.append(failed)

        let pendingEvents = store.pendingEvents()
        XCTAssertEqual(pendingEvents.count, 1, "Permanent failures must not retry")
    }

    func testEventsForOccurrence() {
        store.append(makeEvent(alarmId: "a1", occurrenceId: "occ-A", snoozeNumber: 1))
        store.append(makeEvent(alarmId: "a1", occurrenceId: "occ-A", snoozeNumber: 2))
        store.append(makeEvent(alarmId: "a1", occurrenceId: "occ-B", snoozeNumber: 1))

        XCTAssertEqual(store.eventsForOccurrence("occ-A").count, 2)
        XCTAssertEqual(store.eventsForOccurrence("occ-B").count, 1)
        XCTAssertEqual(store.eventsForOccurrence("occ-C").count, 0)
    }

    func testSnoozeCount() {
        store.append(makeEvent(alarmId: "a1", occurrenceId: "occ-X", snoozeNumber: 1))
        store.append(makeEvent(alarmId: "a1", occurrenceId: "occ-X", snoozeNumber: 2))

        XCTAssertEqual(store.snoozeCount(for: "occ-X"), 2)
        XCTAssertEqual(store.snoozeCount(for: "occ-Y"), 0)
    }

    func testHasEvent() {
        store.append(makeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1))

        XCTAssertTrue(store.hasEvent(occurrenceId: "occ1", snoozeNumber: 1))
        XCTAssertFalse(store.hasEvent(occurrenceId: "occ1", snoozeNumber: 2))
        XCTAssertFalse(store.hasEvent(occurrenceId: "occ-other", snoozeNumber: 1))
    }

    // MARK: - Pruning

    func testPruneOldEvents() {
        var oldEvent = makeEvent(alarmId: "a1", occurrenceId: "old", snoozeNumber: 1)
        // Manually set timestamp to 60 days ago
        oldEvent = SnoozeEvent(
            alarmId: oldEvent.alarmId,
            occurrenceId: oldEvent.occurrenceId,
            snoozeNumber: oldEvent.snoozeNumber,
            timestamp: Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        )
        store.append(oldEvent)

        let recentEvent = makeEvent(alarmId: "a2", occurrenceId: "recent", snoozeNumber: 1)
        store.append(recentEvent)

        store.pruneOldEvents(olderThanDays: 30)

        let remaining = store.loadEvents()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].occurrenceId, "recent")
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        store.append(makeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1))

        // Create a new store instance pointing to the same file
        let store2 = SnoozeEventStore(fileURL: tempURL)
        let events = store2.loadEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].alarmId, "a1")
    }

    // MARK: - Helpers

    private func makeEvent(alarmId: String, occurrenceId: String, snoozeNumber: Int) -> SnoozeEvent {
        SnoozeEvent(
            alarmId: alarmId,
            occurrenceId: occurrenceId,
            snoozeNumber: snoozeNumber
        )
    }
}
