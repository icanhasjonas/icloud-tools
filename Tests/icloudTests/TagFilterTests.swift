import XCTest
@testable import icloud

final class TagFilterTests: XCTestCase {
    func testSingleTagOr() {
        let f = TagFilter.parse(["Green", "Red"])
        XCTAssertTrue(f.matches(["green"]))
        XCTAssertTrue(f.matches(["Red"]))
        XCTAssertFalse(f.matches(["Blue"]))
        XCTAssertFalse(f.matches([]))
    }

    func testAndComboWithPlus() {
        let f = TagFilter.parse(["Green+Important"])
        XCTAssertTrue(f.matches(["green", "important", "other"]))
        XCTAssertFalse(f.matches(["green"]))
        XCTAssertFalse(f.matches(["important"]))
    }

    func testOrOfAndGroups() {
        let f = TagFilter.parse(["Green+Important", "Red"])
        XCTAssertTrue(f.matches(["green", "important"]))
        XCTAssertTrue(f.matches(["red"]))
        XCTAssertFalse(f.matches(["green"]))
    }

    func testCaseInsensitive() {
        let f = TagFilter.parse(["GREEN"])
        XCTAssertTrue(f.matches(["green"]))
        XCTAssertTrue(f.matches(["Green"]))
    }

    func testWhitespaceTrim() {
        let f = TagFilter.parse(["Green + Important"])
        XCTAssertTrue(f.matches(["green", "important"]))
    }
}
