import XCTest

@testable import iGestures

final class ShortcutExecutorTests: XCTestCase {
  func testEventSequenceContainsMarkedKeyDownAndKeyUp() {
    let shortcut = KeyboardShortcut(
      keyCode: 12,
      modifiers: 0x18_0000
    )

    let events = SystemShortcutExecutor.eventSequence(for: shortcut)

    XCTAssertEqual(
      events,
      [
        KeyboardEventDescriptor(
          keyCode: 12,
          modifiers: 0x18_0000,
          isKeyDown: true,
          sourceUserData: EventSourceMarker.syntheticEventUserData
        ),
        KeyboardEventDescriptor(
          keyCode: 12,
          modifiers: 0x18_0000,
          isKeyDown: false,
          sourceUserData: EventSourceMarker.syntheticEventUserData
        ),
      ]
    )
  }

  func testInvalidShortcutProducesNoEvents() {
    XCTAssertTrue(
      SystemShortcutExecutor.eventSequence(
        for: KeyboardShortcut(keyCode: .max, modifiers: 0)
      ).isEmpty
    )
  }
}
