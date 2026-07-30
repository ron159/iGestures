import AppKit
import XCTest

@testable import iGestures

@MainActor
final class SettingsWindowConfigurationTests: XCTestCase {
  func testConfigurationAllowsDynamicResizing() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 700),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )

    SettingsWindowConfiguration.apply(to: window)

    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertEqual(
      window.contentMinSize,
      SettingsWindowConfiguration.minimumContentSize
    )
    XCTAssertGreaterThan(window.contentMaxSize.width, 1_100)
    XCTAssertGreaterThan(window.contentMaxSize.height, 700)
  }
}
