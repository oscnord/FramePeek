import XCTest
@testable import FramePeek

final class BinarySearchUtilsTests: XCTestCase {

    struct TimedItem {
        let time: Double
        let value: Int
    }

    let items: [TimedItem] = [
        TimedItem(time: 0.0, value: 0),
        TimedItem(time: 1.0, value: 1),
        TimedItem(time: 2.0, value: 2),
        TimedItem(time: 3.0, value: 3),
        TimedItem(time: 5.0, value: 5),
        TimedItem(time: 8.0, value: 8),
        TimedItem(time: 13.0, value: 13),
    ]

    func testBinarySearchClosestExactMatch() {
        let idx = binarySearchClosest(in: items, targetTime: 3.0, timeKeyPath: \.time)
        XCTAssertEqual(idx, 3)
    }

    func testBinarySearchClosestBetween() {
        let idx = binarySearchClosest(in: items, targetTime: 2.3, timeKeyPath: \.time)
        XCTAssertEqual(idx, 2) // 2.0 is closer than 3.0 (distance 0.3 vs 0.7)
    }

    func testBinarySearchClosestBeyondEnd() {
        let idx = binarySearchClosest(in: items, targetTime: 100.0, timeKeyPath: \.time)
        XCTAssertEqual(idx, 6) // last element
    }

    func testBinarySearchClosestBeforeStart() {
        let idx = binarySearchClosest(in: items, targetTime: -1.0, timeKeyPath: \.time)
        XCTAssertEqual(idx, 0) // first element
    }

    func testBinarySearchClosestEmpty() {
        let idx = binarySearchClosest(in: [TimedItem](), targetTime: 1.0, timeKeyPath: \.time)
        XCTAssertNil(idx)
    }

    func testLowerBound() {
        XCTAssertEqual(lowerBound(in: items, targetTime: 2.5, timeKeyPath: \.time), 3)
        XCTAssertEqual(lowerBound(in: items, targetTime: 2.0, timeKeyPath: \.time), 2)
        XCTAssertEqual(lowerBound(in: items, targetTime: 0.0, timeKeyPath: \.time), 0)
    }

    func testLowerBoundBeyondEnd() {
        XCTAssertEqual(lowerBound(in: items, targetTime: 100.0, timeKeyPath: \.time), 7)
    }

    func testIndicesInRange() {
        let range = indicesInRange(in: items, from: 1.0, to: 5.0, timeKeyPath: \.time)
        XCTAssertEqual(range, 1..<5) // indices 1,2,3,4 (times 1,2,3,5)
    }

    func testIndicesInRangeEmpty() {
        let range = indicesInRange(in: items, from: 6.0, to: 7.0, timeKeyPath: \.time)
        XCTAssertEqual(range, 5..<5) // no elements between 6 and 7
    }

    func testInterpolationPair() {
        let result = binarySearchInterpolationPair(in: items, targetTime: 1.5, timeKeyPath: \.time)
        XCTAssertNotNil(result)
        if let (before, after, t) = result {
            XCTAssertEqual(before.time, 1.0)
            XCTAssertEqual(after.time, 2.0)
            XCTAssertEqual(t, 0.5, accuracy: 0.001)
        }
    }

    func testInterpolationPairBeforeFirst() {
        let result = binarySearchInterpolationPair(in: items, targetTime: -1.0, timeKeyPath: \.time)
        XCTAssertNil(result)
    }

    func testInterpolationPairAfterLast() {
        let result = binarySearchInterpolationPair(in: items, targetTime: 100.0, timeKeyPath: \.time)
        XCTAssertNil(result)
    }

    func testBinarySearchClosestSingleElement() {
        let single = [TimedItem(time: 5.0, value: 5)]
        XCTAssertEqual(binarySearchClosest(in: single, targetTime: 3.0, timeKeyPath: \.time), 0)
        XCTAssertEqual(binarySearchClosest(in: single, targetTime: 7.0, timeKeyPath: \.time), 0)
    }
}
