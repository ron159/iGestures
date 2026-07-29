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

  func testSecondaryScreenPointUsesItsOwnCoordinateSpace() {
    let secondaryFrame = CGRect(
      x: -1_280,
      y: 0,
      width: 1_280,
      height: 1_024
    )
    let layout = ScreenLayout(screens: [
      .init(
        displayID: 1,
        appKitFrame: CGRect(
          x: 0,
          y: 0,
          width: 1_920,
          height: 1_080
        ),
        quartzFrame: CGRect(
          x: 0,
          y: 0,
          width: 1_920,
          height: 1_080
        ),
        scale: 2
      ),
      .init(
        displayID: 2,
        appKitFrame: secondaryFrame,
        quartzFrame: CGRect(
          x: -1_280,
          y: 56,
          width: 1_280,
          height: 1_024
        ),
        scale: 1
      ),
    ])

    let localPoint = layout.localPoint(
      for: point(-1_200, 100),
      relativeTo: secondaryFrame
    )

    XCTAssertEqual(localPoint.x, 80, accuracy: 0.001)
    XCTAssertEqual(localPoint.y, 980, accuracy: 0.001)
  }

  func testDiagnosticsUseFIFOWithoutCapturingGestureContent() {
    let buffer = GestureDiagnosticsBuffer(capacity: 3)
    let recorder = DiagnosticSnapshotRecorder()
    buffer.setHandler { records in
      recorder.record(records)
    }

    buffer.show(.noMatch)
    buffer.show(.ambiguous)
    buffer.show(.executed(mappingName: "Back"))
    buffer.show(.actionFailed(mappingName: "Open"))

    let records = recorder.latest
    XCTAssertEqual(records.count, 3)
    XCTAssertEqual(
      records.map(\.outcome),
      [.ambiguous, .executed, .actionFailed]
    )
    XCTAssertEqual(records[1].mappingName, "Back")
  }

  private func point(_ x: Float, _ y: Float) -> GesturePoint {
    GesturePoint(x: x, y: y)
  }
}

private final class DiagnosticSnapshotRecorder:
  @unchecked Sendable
{
  private let lock = NSLock()
  private var records: [GestureDiagnosticRecord] = []

  var latest: [GestureDiagnosticRecord] {
    lock.lock()
    defer { lock.unlock() }
    return records
  }

  func record(_ records: [GestureDiagnosticRecord]) {
    lock.lock()
    self.records = records
    lock.unlock()
  }
}
