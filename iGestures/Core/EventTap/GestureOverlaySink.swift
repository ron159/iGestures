import Foundation

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

public enum GestureFeedback: Equatable, Sendable {
  case executed(mappingName: String)
  case noMatch
  case ambiguous
  case actionFailed(mappingName: String)
  case cancelled
}

public protocol GestureFeedbackSinking: Sendable {
  func show(_ feedback: GestureFeedback)
}

public struct NoOpGestureFeedbackSink: GestureFeedbackSinking {
  public init() {}
  public func show(_ feedback: GestureFeedback) {}
}

public final class GestureFeedbackBuffer:
  GestureFeedbackSinking,
  @unchecked Sendable
{
  public typealias Handler = @Sendable (GestureFeedback) -> Void

  private let lock = NSLock()
  private var handler: Handler?
  private var isEnabled = true

  public init() {}

  public func setHandler(_ handler: Handler?) {
    lock.lock()
    self.handler = handler
    lock.unlock()
  }

  public func setEnabled(_ enabled: Bool) {
    lock.lock()
    isEnabled = enabled
    lock.unlock()
  }

  public func show(_ feedback: GestureFeedback) {
    lock.lock()
    let handler = isEnabled ? self.handler : nil
    lock.unlock()
    handler?(feedback)
  }
}

public struct GestureDiagnosticRecord:
  Codable,
  Equatable,
  Identifiable,
  Sendable
{
  public enum Outcome: String, Codable, Sendable {
    case executed
    case noMatch
    case ambiguous
    case actionFailed
    case cancelled
  }

  public let id: UUID
  public let timestamp: Date
  public let outcome: Outcome
  public let mappingName: String?

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    outcome: Outcome,
    mappingName: String? = nil
  ) {
    self.id = id
    self.timestamp = timestamp
    self.outcome = outcome
    self.mappingName = mappingName
  }
}

public final class GestureDiagnosticsBuffer:
  GestureFeedbackSinking,
  @unchecked Sendable
{
  public typealias Handler =
    @Sendable ([GestureDiagnosticRecord]) -> Void

  private let lock = NSLock()
  private let capacity: Int
  private var records: [GestureDiagnosticRecord]
  private var handler: Handler?

  public init(
    capacity: Int = 50,
    initialRecords: [GestureDiagnosticRecord] = []
  ) {
    self.capacity = max(1, capacity)
    self.records = Array(initialRecords.suffix(max(1, capacity)))
  }

  public func setHandler(_ handler: Handler?) {
    lock.lock()
    self.handler = handler
    let records = self.records
    lock.unlock()
    handler?(records)
  }

  public func show(_ feedback: GestureFeedback) {
    let record: GestureDiagnosticRecord
    switch feedback {
    case .executed(let mappingName):
      record = GestureDiagnosticRecord(
        outcome: .executed,
        mappingName: mappingName
      )
    case .noMatch:
      record = GestureDiagnosticRecord(outcome: .noMatch)
    case .ambiguous:
      record = GestureDiagnosticRecord(outcome: .ambiguous)
    case .actionFailed(let mappingName):
      record = GestureDiagnosticRecord(
        outcome: .actionFailed,
        mappingName: mappingName
      )
    case .cancelled:
      record = GestureDiagnosticRecord(outcome: .cancelled)
    }
    lock.lock()
    records.append(record)
    if records.count > capacity {
      records.removeFirst(records.count - capacity)
    }
    let records = self.records
    let handler = self.handler
    lock.unlock()
    handler?(records)
  }

  public func clear() {
    lock.lock()
    records = []
    let handler = self.handler
    lock.unlock()
    handler?([])
  }
}

public struct CompositeGestureFeedbackSink:
  GestureFeedbackSinking,
  Sendable
{
  private let sinks: [any GestureFeedbackSinking]

  public init(_ sinks: [any GestureFeedbackSinking]) {
    self.sinks = sinks
  }

  public func show(_ feedback: GestureFeedback) {
    for sink in sinks {
      sink.show(feedback)
    }
  }
}
