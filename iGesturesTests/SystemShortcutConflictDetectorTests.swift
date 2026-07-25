import CoreGraphics
import XCTest

@testable import iGestures

final class SystemShortcutConflictDetectorTests: XCTestCase {
  private let detector = SystemShortcutConflictDetector()

  func testCommonSystemShortcutsAreReported() {
    XCTAssertEqual(
      detector.conflict(
        for: shortcut(
          keyCode: 49,
          flags: [.maskCommand]
        )
      ),
      .spotlight
    )
    XCTAssertEqual(
      detector.conflict(
        for: shortcut(
          keyCode: 48,
          flags: [.maskCommand, .maskShift]
        )
      ),
      .appSwitcher
    )
    XCTAssertEqual(
      detector.conflict(
        for: shortcut(
          keyCode: 53,
          flags: [.maskCommand, .maskAlternate]
        )
      ),
      .forceQuit
    )
    XCTAssertEqual(
      detector.conflict(
        for: shortcut(
          keyCode: 126,
          flags: [.maskControl]
        )
      ),
      .missionControl
    )
  }

  func testOrdinaryShortcutDoesNotReportConflict() {
    XCTAssertNil(
      detector.conflict(
        for: shortcut(
          keyCode: 12,
          flags: [.maskCommand, .maskShift]
        )
      )
    )
  }

  private func shortcut(
    keyCode: UInt16,
    flags: CGEventFlags
  ) -> KeyboardShortcut {
    KeyboardShortcut(
      keyCode: keyCode,
      modifiers: flags.rawValue
    )
  }
}
