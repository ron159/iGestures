import AppKit
import XCTest

@testable import iGestures

final class ShortcutRecordingSessionTests: XCTestCase {
  @MainActor
  func testRecorderTextDoesNotInterceptClicks() {
    let control = ShortcutRecorderControl(
      frame: NSRect(x: 0, y: 0, width: 120, height: 28)
    )
    control.layoutSubtreeIfNeeded()

    XCTAssertTrue(control.hitTest(NSPoint(x: 60, y: 14)) === control)
  }

  func testRecordingNormalizesModifiersAndStops() {
    var session = ShortcutRecordingSession(
      shortcut: KeyboardShortcut(keyCode: 1, modifiers: 0)
    )
    session.begin()

    let result = session.handleKeyDown(
      keyCode: 12,
      modifiers:
        CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskAlphaShift.rawValue
    )

    XCTAssertEqual(
      result,
      .recorded(
        KeyboardShortcut(
          keyCode: 12,
          modifiers:
            CGEventFlags.maskCommand.rawValue
            | CGEventFlags.maskShift.rawValue
        )
      )
    )
    XCTAssertFalse(session.isRecording)
  }

  func testEscapeCancelsWithoutChangingShortcut() {
    let original = KeyboardShortcut(keyCode: 13, modifiers: 1)
    var session = ShortcutRecordingSession(shortcut: original)
    session.begin()

    XCTAssertEqual(
      session.handleKeyDown(keyCode: 53, modifiers: 0),
      .cancelled
    )
    XCTAssertEqual(session.shortcut, original)
  }

  func testDeleteClearsShortcut() {
    var session = ShortcutRecordingSession(
      shortcut: KeyboardShortcut(keyCode: 13, modifiers: 1)
    )
    session.begin()

    XCTAssertEqual(
      session.handleKeyDown(keyCode: 51, modifiers: 0),
      .cleared
    )
    XCTAssertFalse(session.shortcut.isValid)
  }

  func testKeyDownIsIgnoredUntilRecordingStarts() {
    var session = ShortcutRecordingSession(
      shortcut: KeyboardShortcut(keyCode: 13, modifiers: 1)
    )

    XCTAssertEqual(
      session.handleKeyDown(keyCode: 12, modifiers: 0),
      .ignored
    )
  }

  func testCaptureSuppressesRecordedKeyDownAndMatchingKeyUp() {
    var capture = ShortcutCaptureState()
    capture.begin()

    XCTAssertEqual(
      capture.handleKeyDown(keyCode: 49, modifiers: 1 << 20),
      .captured(keyCode: 49, modifiers: 1 << 20)
    )
    XCTAssertFalse(capture.isRecording)
    XCTAssertEqual(
      capture.handleKeyDown(keyCode: 49, modifiers: 1 << 20),
      .suppress
    )
    XCTAssertEqual(capture.handleKeyUp(keyCode: 49), .suppress)
    XCTAssertEqual(capture.handleKeyUp(keyCode: 49), .passThrough)
  }

  func testCancellingCapturePassesNewKeysThrough() {
    var capture = ShortcutCaptureState()
    capture.begin()
    capture.cancel()

    XCTAssertEqual(
      capture.handleKeyDown(keyCode: 12, modifiers: 0),
      .passThrough
    )
    XCTAssertEqual(capture.handleKeyUp(keyCode: 12), .passThrough)
  }
}
