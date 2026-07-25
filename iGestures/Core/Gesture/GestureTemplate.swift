import Foundation

public struct GestureTemplate: Codable, Hashable, Sendable {
  public let points: [GesturePoint]
  public let aspectRatio: Float
  public let startDirection: GesturePoint
  public let endDirection: GesturePoint

  public init(
    points: [GesturePoint],
    aspectRatio: Float,
    startDirection: GesturePoint,
    endDirection: GesturePoint
  ) {
    self.points = points
    self.aspectRatio = aspectRatio
    self.startDirection = startDirection
    self.endDirection = endDirection
  }
}
