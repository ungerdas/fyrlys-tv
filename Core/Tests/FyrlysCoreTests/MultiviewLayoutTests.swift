import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import FyrlysCore

final class MultiviewLayoutTests: XCTestCase {
    let tv = CGSize(width: 1920, height: 1080)
    let phone = CGSize(width: 430, height: 760)

    private func assertInside(_ frames: [CGRect], _ size: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5)
        for (i, frame) in frames.enumerated() {
            XCTAssertTrue(bounds.contains(frame), "bilde \(i) utenfor: \(frame)", file: file, line: line)
            for other in frames[(i + 1)...] {
                XCTAssertFalse(frame.insetBy(dx: 0.5, dy: 0.5).intersects(other), "bildene overlapper", file: file, line: line)
            }
        }
    }

    func testAllLayoutsFitAndDoNotOverlap() {
        for layout in MultiviewLayout.allCases {
            for count in 1...4 {
                for size in [tv, phone, CGSize(width: 1194, height: 780)] {
                    let frames = multiviewFrames(layout, count: count, in: size)
                    XCTAssertEqual(frames.count, count)
                    assertInside(frames, size)
                }
            }
        }
    }

    func testSideHasOneBigAndSmallOnes() {
        let frames = multiviewFrames(.side, count: 2, in: tv)
        XCTAssertGreaterThan(frames[0].width, frames[1].width * 2)
        XCTAssertLessThan(frames[0].maxX, frames[1].minX)
        // 16:9
        XCTAssertEqual(frames[1].height / frames[1].width, 9.0 / 16.0, accuracy: 0.01)
        let four = multiviewFrames(.side, count: 4, in: tv)
        XCTAssertEqual(Set(four.dropFirst().map(\.minX)).count, 1, "de små står i én kolonne")
    }

    func testTopHasOneBigOverARow() {
        let frames = multiviewFrames(.top, count: 3, in: tv)
        XCTAssertLessThan(frames[0].maxY, frames[1].minY)
        XCTAssertEqual(frames[1].minY, frames[2].minY)
        XCTAssertGreaterThan(frames[0].width, frames[1].width)
        // de to små er midtstilt
        XCTAssertEqual(frames[1].minX, tv.width - frames[2].maxX, accuracy: 0.5)
    }

    func testSideBecomesTopWhenStanding() {
        XCTAssertEqual(multiviewFrames(.side, count: 3, in: phone), multiviewFrames(.top, count: 3, in: phone))
        let frames = multiviewFrames(.top, count: 2, in: phone)
        XCTAssertEqual(frames[0].width, phone.width)
        XCTAssertLessThan(frames[1].width, phone.width)
    }

    func testGridIsLikeBefore() {
        let two = multiviewFrames(.grid, count: 2, in: tv)
        XCTAssertEqual(two[0].width, two[1].width)
        XCTAssertEqual(two[0].height, tv.height)
        let standing = multiviewFrames(.grid, count: 2, in: phone)
        XCTAssertEqual(standing[0].width, phone.width)
        XCTAssertEqual(multiviewFrames(.grid, count: 3, in: tv)[2].minX, 0)
    }
}
