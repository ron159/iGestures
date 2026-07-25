import Foundation

public struct GesturePoint: Codable, Hashable, Sendable {
  public let x: Float
  public let y: Float

  public init(x: Float, y: Float) {
    self.x = x
    self.y = y
  }
}

extension GesturePoint {
  var isFinite: Bool {
    x.isFinite && y.isFinite
  }

  func distance(to other: GesturePoint) -> Float {
    hypotf(other.x - x, other.y - y)
  }

  func interpolated(to other: GesturePoint, fraction: Float) -> GesturePoint {
    GesturePoint(
      x: x + ((other.x - x) * fraction),
      y: y + ((other.y - y) * fraction)
    )
  }

  func normalized() -> GesturePoint {
    let magnitude = hypotf(x, y)
    guard magnitude > Float.ulpOfOne else {
      return GesturePoint(x: 0, y: 0)
    }
    return GesturePoint(x: x / magnitude, y: y / magnitude)
  }
}
