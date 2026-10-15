import XCTest
@testable import Sloozly

final class UUIDv5Tests: XCTestCase {

    func testStableUUIDIsDeterministic() {
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let uuid1 = UUID.v5(namespace: namespace, name: "sloozly.alarm.abc123")
        let uuid2 = UUID.v5(namespace: namespace, name: "sloozly.alarm.abc123")
        XCTAssertEqual(uuid1, uuid2)
    }

    func testStableUUIDDiffersForDifferentNames() {
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let uuid1 = UUID.v5(namespace: namespace, name: "sloozly.alarm.abc")
        let uuid2 = UUID.v5(namespace: namespace, name: "sloozly.alarm.xyz")
        XCTAssertNotEqual(uuid1, uuid2)
    }

    func testStableUUIDIsVersion5() {
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let uuid = UUID.v5(namespace: namespace, name: "test")
        let str = uuid.uuidString
        // Version nibble is character at index 14 (0-based) in the formatted string
        // Format: XXXXXXXX-XXXX-5XXX-XXXX-XXXXXXXXXXXX
        let versionChar = str[str.index(str.startIndex, offsetBy: 14)]
        XCTAssertEqual(String(versionChar), "5", "UUID version nibble should be 5")
    }

    func testStableUUIDIsVariant1() {
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let uuid = UUID.v5(namespace: namespace, name: "test")
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        let variant = (bytes[8] & 0xC0) >> 6
        XCTAssertEqual(variant, 2, "UUID variant bits should be 10 (value 2)")
    }
}
