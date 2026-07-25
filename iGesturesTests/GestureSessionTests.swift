import XCTest

@testable import iGestures

final class GestureSessionTests: XCTestCase {
  func testDisabledSessionPassesEveryEventThrough() {
    var session = GestureSession()

    XCTAssertEqual(
      session.rightMouseDown(
        at: point(0, 0),
        timestamp: 0,
        frontmostBundleID: "com.apple.finder",
        shouldTrack: false
      ),
      .passThrough
    )
    XCTAssertEqual(
      session.rightMouseDragged(to: point(100, 0), timestamp: 0.1),
      .passThrough
    )
    XCTAssertEqual(
      session.rightMouseUp(at: point(100, 0), timestamp: 0.2),
      .passThrough
    )
    XCTAssertEqual(session.state, .idle)
  }

  func testOrdinaryRightClickIsReplayed() {
    var session = GestureSession()

    XCTAssertEqual(
      session.rightMouseDown(
        at: point(10, 20),
        timestamp: 1,
        frontmostBundleID: "com.apple.finder",
        shouldTrack: true
      ).disposition,
      .suppress
    )
    let result = session.rightMouseUp(
      at: point(12, 21),
      timestamp: 1.1
    )

    XCTAssertEqual(result.disposition, .suppress)
    XCTAssertEqual(
      result.commands,
      [.replayPendingRightClick(mouseUpLocation: point(12, 21))]
    )
    XCTAssertEqual(session.state, .idle)
  }

  func testCrossingDeadZoneStartsTracking() {
    var session = GestureSession(
      configuration: .init(activationDistance: 20)
    )
    _ = session.rightMouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )

    let result = session.rightMouseDragged(
      to: point(25, 0),
      timestamp: 0.1
    )

    XCTAssertEqual(session.state, .tracking)
    XCTAssertEqual(
      result.commands,
      [
        .showOverlay(at: point(0, 0)),
        .appendOverlayPoint(point(25, 0)),
      ]
    )
  }

  func testMouseUpFinishesOnlyOnce() {
    var session = GestureSession(
      configuration: .init(activationDistance: 20)
    )
    _ = session.rightMouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )
    _ = session.rightMouseDragged(
      to: point(30, 0),
      timestamp: 0.1
    )

    let first = session.rightMouseUp(
      at: point(40, 0),
      timestamp: 0.2
    )
    let second = session.rightMouseUp(
      at: point(40, 0),
      timestamp: 0.3
    )

    XCTAssertEqual(first.commands.first, .hideOverlay)
    guard case .recognize = first.commands.last else {
      return XCTFail("Expected a recognition command")
    }
    XCTAssertEqual(second, .passThrough)
    XCTAssertEqual(session.state, .idle)
  }

  func testTapDisabledFailsOpenAndResets() {
    var session = GestureSession(
      configuration: .init(activationDistance: 20)
    )
    _ = session.rightMouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )
    _ = session.rightMouseDragged(
      to: point(30, 0),
      timestamp: 0.1
    )

    let result = session.cancel(
      .tapDisabledByTimeout,
      at: point(30, 0)
    )

    XCTAssertEqual(
      result.commands,
      [
        .replayPendingRightClick(mouseUpLocation: point(30, 0)),
        .hideOverlay,
        .didFailOpen(.tapDisabledByTimeout),
      ]
    )
    XCTAssertEqual(session.state, .idle)
  }

  func testDurationLimitFailsOpenAndResets() {
    var session = GestureSession(
      configuration: .init(maximumDuration: 0.1)
    )
    _ = session.rightMouseDown(
      at: point(0, 0),
      timestamp: 1,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )

    let result = session.rightMouseDragged(
      to: point(30, 0),
      timestamp: 1.2
    )

    XCTAssertEqual(result.disposition, .suppress)
    XCTAssertEqual(
      result.commands,
      [
        .replayPendingRightClick(mouseUpLocation: point(30, 0)),
        .didFailOpen(.durationExceeded),
      ]
    )
    XCTAssertEqual(session.state, .idle)
  }

  func testSyntheticEventsPassThroughWithoutChangingState() {
    var session = GestureSession()
    _ = session.rightMouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )

    let result = session.rightMouseUp(
      at: point(0, 0),
      timestamp: 0.1,
      sourceUserData: EventSourceMarker.syntheticEventUserData
    )

    XCTAssertEqual(result, .passThrough)
    XCTAssertEqual(session.state, .pendingRightClick)
  }

  func testPointBufferRemainsBounded() {
    var session = GestureSession(
      configuration: .init(
        activationDistance: 1,
        minimumSampleDistance: 0,
        maximumPointCount: 8
      )
    )
    _ = session.rightMouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: nil,
      shouldTrack: true
    )
    for index in 1...100 {
      _ = session.rightMouseDragged(
        to: point(Float(index), 0),
        timestamp: Double(index) * 0.01
      )
    }

    let result = session.rightMouseUp(
      at: point(101, 0),
      timestamp: 1.1
    )
    guard case .recognize(let candidate) = result.commands.last else {
      return XCTFail("Expected a recognition command")
    }
    XCTAssertLessThanOrEqual(candidate.points.count, 8)
  }

  private func point(_ x: Float, _ y: Float) -> GesturePoint {
    GesturePoint(x: x, y: y)
  }
}
