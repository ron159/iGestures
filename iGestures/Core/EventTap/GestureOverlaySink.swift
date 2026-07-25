public protocol GestureOverlaySinking: Sendable {
  func show(at point: GesturePoint)
  func append(_ point: GesturePoint)
  func hide()
}

public struct NoOpGestureOverlaySink: GestureOverlaySinking {
  public init() {}

  public func show(at point: GesturePoint) {}
  public func append(_ point: GesturePoint) {}
  public func hide() {}
}
