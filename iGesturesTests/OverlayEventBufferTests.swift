import XCTest

@testable import iGestures

final class OverlayEventBufferTests: XCTestCase {
  func testPointsAreCoalescedUntilDisplayDrain() {
    let buffer = OverlayEventBuffer()
    buffer.show(at: point(0, 0))
    buffer.append(point(1, 1))
    buffer.append(point(2, 2))

    XCTAssertEqual(
      buffer.drain(),
      OverlayUpdateBatch(
        startPoint: point(0, 0),
        points: [point(1, 1), point(2, 2)],
        shouldHide: false
      )
    )
    XCTAssertNil(buffer.drain())
  }

  func testHideIsDeliveredWithLastPendingFrame() {
    let buffer = OverlayEventBuffer()
    buffer.show(at: point(0, 0))
    buffer.append(point(1, 1))
    buffer.hide()

    XCTAssertEqual(
      buffer.drain(),
      OverlayUpdateBatch(
        startPoint: point(0, 0),
        points: [point(1, 1)],
        shouldHide: true
      )
    )
  }

  func testInactiveBufferDropsStrayPoints() {
    let buffer = OverlayEventBuffer()
    buffer.append(point(1, 1))

    XCTAssertNil(buffer.drain())
  }

  func testDisablingActiveOverlayHidesAndIgnoresNewPoints() {
    let buffer = OverlayEventBuffer()
    buffer.show(at: point(0, 0))
    buffer.append(point(1, 1))

    buffer.setEnabled(false)

    XCTAssertEqual(
      buffer.drain(),
      OverlayUpdateBatch(
        startPoint: nil,
        points: [],
        shouldHide: true
      )
    )
    buffer.show(at: point(2, 2))
    buffer.append(point(3, 3))
    XCTAssertNil(buffer.drain())

    buffer.setEnabled(true)
    buffer.show(at: point(4, 4))
    XCTAssertEqual(buffer.drain()?.startPoint, point(4, 4))
  }

  func testPendingPointsStayBoundedWhenDisplayDrainIsDelayed() {
    let maximumPointCount = 8
    let buffer = OverlayEventBuffer(
      maximumPendingPointCount: maximumPointCount
    )
    buffer.show(at: point(0, 0))
    for index in 1...1_000 {
      buffer.append(point(Float(index), Float(index)))
    }

    let batch = buffer.drain()

    XCTAssertNotNil(batch)
    XCTAssertLessThanOrEqual(
      batch?.points.count ?? .max,
      maximumPointCount
    )
    XCTAssertEqual(batch?.points.first, point(1, 1))
    XCTAssertEqual(batch?.points.last, point(1_000, 1_000))
  }

  private func point(_ x: Float, _ y: Float) -> GesturePoint {
    GesturePoint(x: x, y: y)
  }
}
