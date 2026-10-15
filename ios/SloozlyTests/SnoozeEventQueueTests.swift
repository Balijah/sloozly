import XCTest
@testable import Sloozly

final class SnoozeEventQueueTests: XCTestCase {
    @MainActor
    func testSameEventIsSentOnlyOnce() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SnoozeEventStore(fileURL: url)
        var calls = 0
        let queue = SnoozeEventQueue(store: store) { event in
            calls += 1
            return self.response(for: event)
        }
        await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)
        await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.snoozeCount(for: "occ1"), 1)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    @MainActor
    func testPermanentFailureDoesNotRetry() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SnoozeEventStore(fileURL: url)
        var calls = 0
        let queue = SnoozeEventQueue(store: store) { _ in
            calls += 1
            throw APIError.forbidden
        }
        await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1)
        await queue.processQueue()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.loadEvents().first?.status, .failed)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    @MainActor
    func testRecoveredInterruptedSendKeepsItsOriginalIdentity() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let first = SnoozeEventStore(fileURL: url)
        var event = SnoozeEvent(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 2)
        event.status = .sending
        first.append(event)
        let restarted = SnoozeEventStore(fileURL: url)
        var sentIDs: [UUID] = []
        let queue = SnoozeEventQueue(store: restarted) { recovered in
            sentIDs.append(recovered.id)
            XCTAssertEqual(recovered.snoozeNumber, 2)
            return self.response(for: recovered)
        }
        await queue.processQueue()
        XCTAssertEqual(sentIDs, [event.id])
        XCTAssertEqual(restarted.loadEvents().first?.status, .sent)
    }

    @MainActor
    func testEventsAppendedDuringSendAreAlsoProcessed() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SnoozeEventStore(fileURL: url)
        var resume: CheckedContinuation<Void, Never>?
        var numbers: [Int] = []
        let queue = SnoozeEventQueue(store: store) { event in
            numbers.append(event.snoozeNumber)
            if event.snoozeNumber == 1 {
                await withCheckedContinuation { resume = $0 }
            }
            return self.response(for: event)
        }
        let first = Task { await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 1) }
        while resume == nil { await Task.yield() }
        await queue.recordSnooze(alarmId: "a1", occurrenceId: "occ1", snoozeNumber: 2)
        resume?.resume()
        await first.value
        XCTAssertEqual(numbers, [1, 2])
        XCTAssertEqual(queue.pendingCount, 0)
    }

    private func response(for event: SnoozeEvent) -> TriggerPenaltyResponse {
        TriggerPenaltyResponse(penaltyId: "p1", amount: 500, amountFormatted: "$5.00",
                               snoozeNumber: event.snoozeNumber, status: .processing, triggeredAt: Date())
    }
}
