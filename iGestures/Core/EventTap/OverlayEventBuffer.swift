import Foundation

public struct OverlayUpdateBatch: Equatable, Sendable {
  public let startPoint: GesturePoint?
  public let points: [GesturePoint]
  public let shouldHide: Bool

  public init(
    startPoint: GesturePoint?,
    points: [GesturePoint],
    shouldHide: Bool
  ) {
    self.startPoint = startPoint
    self.points = points
    self.shouldHide = shouldHide
  }
}

public final class OverlayEventBuffer:
  GestureOverlaySinking,
  @unchecked Sendable
{
  public typealias WakeHandler = @Sendable () -> Void

  private let lock = NSLock()
  private let maximumPendingPointCount: Int
  private var wakeHandler: WakeHandler?
  private var isEnabled = true
  private var isActive = false
  private var pendingStartPoint: GesturePoint?
  private var pendingPoints: [GesturePoint] = []
  private var pendingHide = false

  public init(maximumPendingPointCount: Int = 512) {
    self.maximumPendingPointCount = max(
      8,
      maximumPendingPointCount
    )
    pendingPoints.reserveCapacity(self.maximumPendingPointCount)
  }

  public func setWakeHandler(_ handler: WakeHandler?) {
    lock.lock()
    wakeHandler = handler
    lock.unlock()
  }

  public func setEnabled(_ isEnabled: Bool) {
    lock.lock()
    self.isEnabled = isEnabled
    let shouldHide =
      !isEnabled
      && (isActive || pendingStartPoint != nil || !pendingPoints.isEmpty)
    if shouldHide {
      isActive = false
      pendingStartPoint = nil
      pendingPoints.removeAll(keepingCapacity: true)
      pendingHide = true
    }
    let handler = shouldHide ? wakeHandler : nil
    lock.unlock()
    handler?()
  }

  public func show(at point: GesturePoint) {
    lock.lock()
    guard isEnabled else {
      lock.unlock()
      return
    }
    isActive = true
    pendingStartPoint = point
    pendingPoints.removeAll(keepingCapacity: true)
    pendingHide = false
    let handler = wakeHandler
    lock.unlock()
    handler?()
  }

  public func append(_ point: GesturePoint) {
    lock.lock()
    if isEnabled && isActive {
      if pendingPoints.count >= maximumPendingPointCount {
        downsamplePendingPoints()
      }
      pendingPoints.append(point)
    }
    lock.unlock()
  }

  public func hide() {
    lock.lock()
    let hadPendingUpdate =
      isActive || pendingStartPoint != nil || !pendingPoints.isEmpty
    isActive = false
    pendingHide = hadPendingUpdate
    let handler = hadPendingUpdate ? wakeHandler : nil
    lock.unlock()
    handler?()
  }

  public func drain() -> OverlayUpdateBatch? {
    lock.lock()
    defer { lock.unlock() }
    guard
      pendingStartPoint != nil
        || !pendingPoints.isEmpty
        || pendingHide
    else {
      return nil
    }

    let batch = OverlayUpdateBatch(
      startPoint: pendingStartPoint,
      points: pendingPoints,
      shouldHide: pendingHide
    )
    pendingStartPoint = nil
    pendingPoints.removeAll(keepingCapacity: true)
    pendingHide = false
    return batch
  }

  private func downsamplePendingPoints() {
    let targetCount = max(2, maximumPendingPointCount / 2)
    guard pendingPoints.count > targetCount else { return }

    let scale =
      Float(pendingPoints.count - 1) / Float(targetCount - 1)
    var reduced: [GesturePoint] = []
    reduced.reserveCapacity(maximumPendingPointCount)
    for index in 0..<targetCount {
      let sourceIndex = min(
        pendingPoints.count - 1,
        Int((Float(index) * scale).rounded())
      )
      reduced.append(pendingPoints[sourceIndex])
    }
    pendingPoints = reduced
  }
}
