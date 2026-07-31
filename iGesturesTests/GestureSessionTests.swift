import CoreGraphics
import XCTest

@testable import iGestures

final class GestureSessionTests: XCTestCase {
  func testSecondaryTriggerIsOptionalAndCannotConflict() {
    XCTAssertNil(
      GestureInputConfiguration(
        triggerButton: .right,
        secondaryTriggerButton: .right
      ).secondaryTriggerButton
    )
    XCTAssertNil(
      GestureInputConfiguration(
        secondaryTriggerButton: .trackpad
      ).secondaryTriggerButton
    )
    XCTAssertEqual(
      GestureInputConfiguration(
        triggerButton: .right,
        secondaryTriggerButton: .button4
      ).secondaryTriggerButton,
      .button4
    )
  }

  func testTriggerButtonMatchesOnlyItsMouseEvents() {
    XCTAssertEqual(
      GestureTriggerButton.left.eventPhase(
        for: .leftMouseDown,
        buttonNumber: 0
      ),
      .down
    )
    XCTAssertEqual(
      GestureTriggerButton.right.eventPhase(
        for: .rightMouseDown,
        buttonNumber: 1
      ),
      .down
    )
    XCTAssertNil(
      GestureTriggerButton.right.eventPhase(
        for: .otherMouseDown,
        buttonNumber: 2
      )
    )
    XCTAssertEqual(
      GestureTriggerButton.middle.eventPhase(
        for: .otherMouseDragged,
        buttonNumber: 2
      ),
      .dragged
    )
    XCTAssertNil(
      GestureTriggerButton.middle.eventPhase(
        for: .otherMouseDragged,
        buttonNumber: 3
      )
    )
    XCTAssertEqual(
      GestureTriggerButton(buttonNumber: 7).eventPhase(
        for: .otherMouseUp,
        buttonNumber: 7
      ),
      .up
    )
  }

  func testKeyboardTriggerUsesStableEncodedIdentifier() {
    let trigger = GestureTriggerButton.keyboard(keyCode: 49)

    XCTAssertEqual(trigger.keyboardKeyCode, 49)
    XCTAssertNil(GestureTriggerButton.right.keyboardKeyCode)
    XCTAssertNil(GestureTriggerButton.trackpad.keyboardKeyCode)
    XCTAssertNil(
      GestureTriggerButton(
        buttonNumber: 0xFFFF_0001
      ).keyboardKeyCode
    )
    XCTAssertNil(
      trigger.eventPhase(
        for: .otherMouseDown,
        buttonNumber: Int64(trigger.buttonNumber)
      )
    )
  }

  func testTriggerButtonCaptureAcceptsAnyPhysicalButton() {
    var capture = TriggerButtonCaptureState()
    capture.begin()

    XCTAssertEqual(
      capture.handleMouseDown(buttonNumber: 7),
      .captured(GestureTriggerButton(buttonNumber: 7))
    )
    XCTAssertFalse(capture.isRecording)
    XCTAssertEqual(
      capture.handleMouseDragged(buttonNumber: 7),
      .suppress
    )
    XCTAssertEqual(capture.handleMouseUp(buttonNumber: 7), .suppress)
    XCTAssertEqual(
      capture.handleMouseUp(buttonNumber: 7),
      .passThrough
    )
  }

  func testTriggerButtonCaptureAcceptsKeyboardKeyAndSuppressesKeyUp() {
    var capture = TriggerButtonCaptureState()
    capture.begin()

    XCTAssertEqual(
      capture.handleKeyDown(keyCode: 49),
      .captured(.keyboard(keyCode: 49))
    )
    XCTAssertFalse(capture.isRecording)
    XCTAssertEqual(capture.handleKeyDown(keyCode: 49), .suppress)
    XCTAssertEqual(capture.handleKeyUp(keyCode: 49), .suppress)
    XCTAssertEqual(capture.handleKeyUp(keyCode: 49), .passThrough)
  }

  func testTriggerButtonCaptureKeepsEscapeAvailableForCancellation() {
    var capture = TriggerButtonCaptureState()
    capture.begin()

    XCTAssertEqual(capture.handleKeyDown(keyCode: 53), .passThrough)
    XCTAssertTrue(capture.isRecording)
  }

  func testDisabledSessionPassesEveryEventThrough() {
    var session = GestureSession()

    XCTAssertEqual(
      session.mouseDown(
        at: point(0, 0),
        timestamp: 0,
        frontmostBundleID: "com.apple.finder",
        shouldTrack: false
      ),
      .passThrough
    )
    XCTAssertEqual(
      session.mouseDragged(to: point(100, 0), timestamp: 0.1),
      .passThrough
    )
    XCTAssertEqual(
      session.mouseUp(at: point(100, 0), timestamp: 0.2),
      .passThrough
    )
    XCTAssertEqual(session.state, .idle)
  }

  func testOrdinaryRightClickIsReplayed() {
    var session = GestureSession()

    XCTAssertEqual(
      session.mouseDown(
        at: point(10, 20),
        timestamp: 1,
        frontmostBundleID: "com.apple.finder",
        shouldTrack: true
      ).disposition,
      .suppress
    )
    let result = session.mouseUp(
      at: point(12, 21),
      timestamp: 1.1
    )

    XCTAssertEqual(result.disposition, .suppress)
    XCTAssertEqual(
      result.commands,
      [.replayPendingClick(mouseUpLocation: point(12, 21))]
    )
    XCTAssertEqual(session.state, .idle)
  }

  func testCrossingDeadZoneStartsTracking() {
    var session = GestureSession(
      configuration: .init(activationDistance: 20)
    )
    _ = session.mouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )

    let result = session.mouseDragged(
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

  func testGestureStaysPendingUntilEitherActivationThresholdIsReached() {
    var session = GestureSession(
      configuration: .init(
        activationDistance: 20,
        minimumTriggerDuration: 0.2
      )
    )
    _ = session.mouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )

    let earlyDrag = session.mouseDragged(
      to: point(10, 0),
      timestamp: 0.1
    )
    let earlyUp = session.mouseUp(
      at: point(12, 0),
      timestamp: 0.15
    )

    XCTAssertEqual(session.state, .idle)
    XCTAssertTrue(earlyDrag.commands.isEmpty)
    XCTAssertEqual(
      earlyUp.commands,
      [.replayPendingClick(mouseUpLocation: point(12, 0))]
    )
  }

  func testHoldDurationActivatesBeforeMovementThreshold() {
    var session = GestureSession(
      configuration: .init(
        activationDistance: 20,
        minimumTriggerDuration: 0.2
      )
    )
    _ = session.mouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )
    _ = session.mouseDragged(
      to: point(10, 0),
      timestamp: 0.1
    )

    let result = session.mouseDragged(
      to: point(11, 0),
      timestamp: 0.2
    )

    XCTAssertEqual(session.state, .tracking)
    XCTAssertEqual(
      result.commands,
      [
        .showOverlay(at: point(0, 0)),
        .appendOverlayPoint(point(11, 0)),
      ]
    )
  }

  func testMovementThresholdActivatesBeforeHoldDuration() {
    var session = GestureSession(
      configuration: .init(
        activationDistance: 20,
        minimumTriggerDuration: 0.2
      )
    )
    _ = session.mouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )

    let result = session.mouseDragged(
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
    _ = session.mouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )
    _ = session.mouseDragged(
      to: point(30, 0),
      timestamp: 0.1
    )

    let first = session.mouseUp(
      at: point(40, 0),
      timestamp: 0.2
    )
    let second = session.mouseUp(
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
    _ = session.mouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )
    _ = session.mouseDragged(
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
        .replayPendingClick(mouseUpLocation: point(30, 0)),
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
    _ = session.mouseDown(
      at: point(0, 0),
      timestamp: 1,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )

    let result = session.mouseDragged(
      to: point(30, 0),
      timestamp: 1.2
    )

    XCTAssertEqual(result.disposition, .suppress)
    XCTAssertEqual(
      result.commands,
      [
        .replayPendingClick(mouseUpLocation: point(30, 0)),
        .didFailOpen(.durationExceeded),
      ]
    )
    XCTAssertEqual(session.state, .idle)
  }

  func testSyntheticEventsPassThroughWithoutChangingState() {
    var session = GestureSession()
    _ = session.mouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )

    let result = session.mouseUp(
      at: point(0, 0),
      timestamp: 0.1,
      sourceUserData: EventSourceMarker.syntheticEventUserData
    )

    XCTAssertEqual(result, .passThrough)
    XCTAssertEqual(session.state, .pendingClick)
  }

  func testPointBufferRemainsBounded() {
    var session = GestureSession(
      configuration: .init(
        activationDistance: 1,
        minimumSampleDistance: 0,
        maximumPointCount: 8
      )
    )
    _ = session.mouseDown(
      at: point(0, 0),
      timestamp: 0,
      frontmostBundleID: nil,
      shouldTrack: true
    )
    for index in 1...100 {
      _ = session.mouseDragged(
        to: point(Float(index), 0),
        timestamp: Double(index) * 0.01
      )
    }

    let result = session.mouseUp(
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
