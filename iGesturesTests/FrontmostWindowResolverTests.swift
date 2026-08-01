import CoreGraphics
import XCTest

@testable import iGestures

final class FrontmostWindowResolverTests: XCTestCase {
  func testChoosesFirstVisibleApplicationWindowContainingPoint() {
    let point = CGPoint(x: 80, y: 80)
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
    let windows = [
      ApplicationWindowDescriptor(
        bounds: bounds,
        layer: 10,
        ownerPID: 100
      ),
      ApplicationWindowDescriptor(
        bounds: bounds,
        alpha: 0,
        ownerPID: 200
      ),
      ApplicationWindowDescriptor(bounds: bounds, ownerPID: 300),
      ApplicationWindowDescriptor(bounds: bounds, ownerPID: 400),
    ]

    XCTAssertEqual(
      FrontmostWindowResolver.ownerPID(at: point, windows: windows),
      300
    )
  }

  func testReturnsNilWhenPointIsOutsideApplicationWindows() {
    let windows = [
      ApplicationWindowDescriptor(
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        ownerPID: 100
      )
    ]

    XCTAssertNil(
      FrontmostWindowResolver.ownerPID(
        at: CGPoint(x: 200, y: 200),
        windows: windows
      )
    )
  }
}
