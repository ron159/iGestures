import Foundation

public struct GestureTriggerButton:
  Codable,
  Hashable,
  Identifiable,
  Sendable
{
  public static let left = GestureTriggerButton(buttonNumber: 0)
  public static let right = GestureTriggerButton(buttonNumber: 1)
  public static let middle = GestureTriggerButton(buttonNumber: 2)
  public static let button4 = GestureTriggerButton(buttonNumber: 3)
  public static let button5 = GestureTriggerButton(buttonNumber: 4)
  public static let trackpad = GestureTriggerButton(
    buttonNumber: UInt32.max
  )
  public static let commonPresets: [GestureTriggerButton] = [
    .right,
    .middle,
    .button4,
    .button5,
  ]

  public let buttonNumber: UInt32

  public init(buttonNumber: UInt32) {
    self.buttonNumber = buttonNumber
  }

  public var id: UInt32 { buttonNumber }
}

public struct GestureInputConfiguration: Equatable, Sendable {
  public static let defaultTriggerDuration: TimeInterval = 0.15
  public static let minimumTriggerDuration: TimeInterval = 0
  public static let maximumTriggerDuration: TimeInterval = 2
  public static let `default` = GestureInputConfiguration()

  public let triggerButton: GestureTriggerButton
  public let triggerDuration: TimeInterval
  public let isTrackpadGestureEnabled: Bool
  public let trackpadModifiers: UInt64

  public init(
    triggerButton: GestureTriggerButton = .right,
    triggerDuration: TimeInterval = defaultTriggerDuration,
    isTrackpadGestureEnabled: Bool = false,
    trackpadModifiers: UInt64 = 0x8_0000 | 0x4_0000
  ) {
    self.triggerButton = triggerButton
    self.isTrackpadGestureEnabled = isTrackpadGestureEnabled
    self.trackpadModifiers =
      ShortcutRecordingSession.normalizedModifiers(
        trackpadModifiers
      )
    let duration =
      triggerDuration.isFinite
      ? triggerDuration
      : Self.defaultTriggerDuration
    self.triggerDuration = min(
      Self.maximumTriggerDuration,
      max(Self.minimumTriggerDuration, duration)
    )
  }
}

public enum GestureSessionState: Equatable, Sendable {
  case idle
  case pendingClick
  case tracking
  case finishing
  case cancelled
}

public enum GestureEventDisposition: Equatable, Sendable {
  case passThrough
  case suppress
}

public enum GestureCancellationReason: Equatable, Sendable {
  case disabled
  case tapDisabledByTimeout
  case tapDisabledByUserInput
  case permissionLost
  case configurationInvalid
  case applicationTerminating
  case sessionInconsistent
  case durationExceeded
  case userCancelled
}

public struct GestureCandidate: Equatable, Sendable {
  public let points: [GesturePoint]
  public let frontmostBundleID: String?
  public let triggerButton: GestureTriggerButton
  public let inputDevice: GestureInputDevice
  public let duration: TimeInterval

  public init(
    points: [GesturePoint],
    frontmostBundleID: String?,
    triggerButton: GestureTriggerButton = .right,
    inputDevice: GestureInputDevice = .mouse(identifier: nil),
    duration: TimeInterval
  ) {
    self.points = points
    self.frontmostBundleID = frontmostBundleID
    self.triggerButton = triggerButton
    self.inputDevice = inputDevice
    self.duration = duration
  }
}

public enum GestureSessionCommand: Equatable, Sendable {
  case showOverlay(at: GesturePoint)
  case appendOverlayPoint(GesturePoint)
  case hideOverlay
  case replayPendingClick(mouseUpLocation: GesturePoint)
  case recognize(GestureCandidate)
  case didFailOpen(GestureCancellationReason)
}

public struct GestureSessionResult: Equatable, Sendable {
  public let disposition: GestureEventDisposition
  public let commands: [GestureSessionCommand]

  public init(
    disposition: GestureEventDisposition,
    commands: [GestureSessionCommand] = []
  ) {
    self.disposition = disposition
    self.commands = commands
  }

  public static let passThrough = GestureSessionResult(
    disposition: .passThrough
  )
}

public struct GestureSession: Sendable {
  public struct Configuration: Equatable, Sendable {
    public let activationDistance: Float
    public let minimumTriggerDuration: TimeInterval
    public let minimumSampleDistance: Float
    public let maximumPointCount: Int
    public let maximumDuration: TimeInterval

    public init(
      activationDistance: Float = 24,
      minimumTriggerDuration: TimeInterval =
        GestureInputConfiguration.defaultTriggerDuration,
      minimumSampleDistance: Float = 0.5,
      maximumPointCount: Int = 1_024,
      maximumDuration: TimeInterval = 10
    ) {
      self.activationDistance = max(0, activationDistance)
      self.minimumTriggerDuration = max(0, minimumTriggerDuration)
      self.minimumSampleDistance = max(0, minimumSampleDistance)
      self.maximumPointCount = max(8, maximumPointCount)
      self.maximumDuration = max(0.1, maximumDuration)
    }
  }

  public private(set) var state: GestureSessionState = .idle
  public let configuration: Configuration

  private var points: [GesturePoint]
  private var startedAt: TimeInterval?
  private var frontmostBundleID: String?
  private var triggerButton: GestureTriggerButton?
  private var accumulatedDistance: Float = 0

  public init(configuration: Configuration = Configuration()) {
    self.configuration = configuration
    self.points = []
    self.points.reserveCapacity(configuration.maximumPointCount)
  }

  public mutating func mouseDown(
    at point: GesturePoint,
    timestamp: TimeInterval,
    frontmostBundleID: String?,
    shouldTrack: Bool,
    triggerButton: GestureTriggerButton = .right,
    sourceUserData: Int64 = 0
  ) -> GestureSessionResult {
    guard !EventSourceMarker.isSynthetic(sourceUserData) else {
      return .passThrough
    }
    guard state == .idle else {
      return failOpen(
        reason: .sessionInconsistent,
        at: points.last ?? point,
        disposition: .passThrough
      )
    }
    guard shouldTrack else {
      return .passThrough
    }

    state = .pendingClick
    startedAt = timestamp
    self.frontmostBundleID = frontmostBundleID
    self.triggerButton = triggerButton
    accumulatedDistance = 0
    points.removeAll(keepingCapacity: true)
    points.append(point)
    return GestureSessionResult(disposition: .suppress)
  }

  public mutating func mouseDragged(
    to point: GesturePoint,
    timestamp: TimeInterval,
    sourceUserData: Int64 = 0
  ) -> GestureSessionResult {
    guard !EventSourceMarker.isSynthetic(sourceUserData) else {
      return .passThrough
    }

    switch state {
    case .idle:
      return .passThrough
    case .pendingClick, .tracking:
      guard isWithinDuration(timestamp) else {
        return failOpen(
          reason: .durationExceeded,
          at: point,
          disposition: .suppress
        )
      }

      let appended = append(point)
      if state == .pendingClick,
        hasReachedActivationThreshold(timestamp)
      {
        state = .tracking
        return GestureSessionResult(
          disposition: .suppress,
          commands: [
            .showOverlay(at: points[0]),
            .appendOverlayPoint(point),
          ]
        )
      }
      if state == .tracking, appended {
        return GestureSessionResult(
          disposition: .suppress,
          commands: [.appendOverlayPoint(point)]
        )
      }
      return GestureSessionResult(disposition: .suppress)
    case .finishing, .cancelled:
      return failOpen(
        reason: .sessionInconsistent,
        at: point,
        disposition: .passThrough
      )
    }
  }

  public mutating func mouseUp(
    at point: GesturePoint,
    timestamp: TimeInterval,
    sourceUserData: Int64 = 0
  ) -> GestureSessionResult {
    guard !EventSourceMarker.isSynthetic(sourceUserData) else {
      return .passThrough
    }

    switch state {
    case .idle:
      return .passThrough
    case .pendingClick, .tracking:
      guard isWithinDuration(timestamp) else {
        return failOpen(
          reason: .durationExceeded,
          at: point,
          disposition: .suppress
        )
      }

      _ = append(point)
      if state == .pendingClick,
        !hasReachedActivationThreshold(timestamp)
      {
        let result = GestureSessionResult(
          disposition: .suppress,
          commands: [.replayPendingClick(mouseUpLocation: point)]
        )
        reset()
        return result
      }

      state = .finishing
      let candidate = GestureCandidate(
        points: points,
        frontmostBundleID: frontmostBundleID,
        triggerButton: triggerButton ?? .right,
        inputDevice:
          triggerButton == .trackpad
          ? .trackpad
          : .mouse(identifier: nil),
        duration: duration(endingAt: timestamp)
      )
      let result = GestureSessionResult(
        disposition: .suppress,
        commands: [
          .hideOverlay,
          .recognize(candidate),
        ]
      )
      reset()
      return result
    case .finishing, .cancelled:
      return failOpen(
        reason: .sessionInconsistent,
        at: point,
        disposition: .passThrough
      )
    }
  }

  public mutating func cancel(
    _ reason: GestureCancellationReason,
    at point: GesturePoint? = nil
  ) -> GestureSessionResult {
    guard state != .idle else {
      return .passThrough
    }
    return failOpen(
      reason: reason,
      at: point ?? points.last ?? GesturePoint(x: 0, y: 0),
      disposition: .passThrough
    )
  }

  public mutating func abandon() -> GestureSessionResult {
    guard state != .idle else { return .passThrough }
    let shouldHide = state == .tracking || state == .finishing
    reset()
    return GestureSessionResult(
      disposition: .suppress,
      commands: shouldHide ? [.hideOverlay] : []
    )
  }

  private mutating func append(_ point: GesturePoint) -> Bool {
    guard let previous = points.last else {
      points.append(point)
      return true
    }
    let distance = previous.distance(to: point)
    guard distance >= configuration.minimumSampleDistance else {
      return false
    }

    accumulatedDistance += distance
    if points.count >= configuration.maximumPointCount {
      downsample()
    }
    points.append(point)
    return true
  }

  private mutating func downsample() {
    let targetCount = max(2, configuration.maximumPointCount / 2)
    let scale = Float(points.count - 1) / Float(targetCount - 1)
    var reduced: [GesturePoint] = []
    reduced.reserveCapacity(configuration.maximumPointCount)

    for index in 0..<targetCount {
      let sourceIndex = min(
        points.count - 1,
        Int((Float(index) * scale).rounded())
      )
      reduced.append(points[sourceIndex])
    }
    points = reduced
  }

  private func isWithinDuration(_ timestamp: TimeInterval) -> Bool {
    duration(endingAt: timestamp) <= configuration.maximumDuration
  }

  private func hasReachedTriggerDuration(
    _ timestamp: TimeInterval
  ) -> Bool {
    duration(endingAt: timestamp)
      >= configuration.minimumTriggerDuration
  }

  private func hasReachedActivationThreshold(
    _ timestamp: TimeInterval
  ) -> Bool {
    accumulatedDistance >= configuration.activationDistance
      || hasReachedTriggerDuration(timestamp)
  }

  private func duration(endingAt timestamp: TimeInterval) -> TimeInterval {
    guard let startedAt else { return 0 }
    return max(0, timestamp - startedAt)
  }

  private mutating func failOpen(
    reason: GestureCancellationReason,
    at point: GesturePoint,
    disposition: GestureEventDisposition
  ) -> GestureSessionResult {
    let wasTracking = state == .tracking || state == .finishing
    state = .cancelled
    var commands: [GestureSessionCommand] = [
      .replayPendingClick(mouseUpLocation: point)
    ]
    if wasTracking {
      commands.append(.hideOverlay)
    }
    commands.append(.didFailOpen(reason))
    reset()
    return GestureSessionResult(
      disposition: disposition,
      commands: commands
    )
  }

  private mutating func reset() {
    state = .idle
    points.removeAll(keepingCapacity: true)
    startedAt = nil
    frontmostBundleID = nil
    triggerButton = nil
    accumulatedDistance = 0
  }
}
