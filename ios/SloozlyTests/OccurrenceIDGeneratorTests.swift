import XCTest
@testable import Sloozly

final class OccurrenceIDGeneratorTests: XCTestCase {

    // MARK: - Generation

    func testGenerateProducesDeterministicID() {
        let date = makeDate(year: 2026, month: 3, day: 15)
        let id1 = OccurrenceIDGenerator.generate(alarmId: "alarm-abc", date: date)
        let id2 = OccurrenceIDGenerator.generate(alarmId: "alarm-abc", date: date)
        XCTAssertEqual(id1, id2, "Same alarm + date should produce identical occurrence IDs")
    }

    func testGenerateFormatIncludesAlarmIdAndDate() {
        let date = makeDate(year: 2026, month: 7, day: 4)
        let id = OccurrenceIDGenerator.generate(alarmId: "my-alarm-123", date: date)
        XCTAssertEqual(id, "my-alarm-123_2026-07-04")
    }

    func testGenerateDifferentDaysProduceDifferentIDs() {
        let day1 = makeDate(year: 2026, month: 1, day: 1)
        let day2 = makeDate(year: 2026, month: 1, day: 2)
        let id1 = OccurrenceIDGenerator.generate(alarmId: "a1", date: day1)
        let id2 = OccurrenceIDGenerator.generate(alarmId: "a1", date: day2)
        XCTAssertNotEqual(id1, id2)
    }

    func testGenerateDifferentAlarmsProduceDifferentIDs() {
        let date = makeDate(year: 2026, month: 6, day: 1)
        let id1 = OccurrenceIDGenerator.generate(alarmId: "alarm-A", date: date)
        let id2 = OccurrenceIDGenerator.generate(alarmId: "alarm-B", date: date)
        XCTAssertNotEqual(id1, id2)
    }

    func testGenerateWithCurrentDateDoesNotCrash() {
        let id = OccurrenceIDGenerator.generate(alarmId: "test")
        XCTAssertFalse(id.isEmpty)
        XCTAssertTrue(id.hasPrefix("test_"))
    }

    func testGenerateZeroPaddedSingleDigitMonthAndDay() {
        let date = makeDate(year: 2026, month: 1, day: 5)
        let id = OccurrenceIDGenerator.generate(alarmId: "x", date: date)
        XCTAssertEqual(id, "x_2026-01-05")
    }

    // MARK: - Parsing

    func testParseAlarmId() {
        let alarmId = OccurrenceIDGenerator.alarmId(from: "alarm-abc_2026-03-15")
        XCTAssertEqual(alarmId, "alarm-abc")
    }

    func testParseAlarmIdWithUnderscoreInAlarmId() {
        let alarmId = OccurrenceIDGenerator.alarmId(from: "alarm_with_underscores_2026-03-15")
        XCTAssertEqual(alarmId, "alarm_with_underscores")
    }

    func testParseDateString() {
        let dateStr = OccurrenceIDGenerator.dateString(from: "alarm-abc_2026-03-15")
        XCTAssertEqual(dateStr, "2026-03-15")
    }

    func testParseReturnsNilForInvalidFormat() {
        XCTAssertNil(OccurrenceIDGenerator.alarmId(from: "no-underscore"))
        XCTAssertNil(OccurrenceIDGenerator.dateString(from: "no-underscore"))
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 6
        components.minute = 0
        return Calendar.current.date(from: components)!
    }
}
