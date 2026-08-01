import Foundation

public enum RecognitionSensitivity:
  String,
  Codable,
  CaseIterable,
  Sendable
{
  case loose
  case standard
  case strict

  public var configuration: GestureRecognizer.Configuration {
    switch self {
    case .loose:
      GestureRecognizer.Configuration(
        acceptanceThreshold: 0.43,
        ambiguityMargin: 0.04
      )
    case .standard:
      GestureRecognizer.Configuration(
        acceptanceThreshold: 0.35,
        ambiguityMargin: 0.04
      )
    case .strict:
      GestureRecognizer.Configuration(
        acceptanceThreshold: 0.27,
        ambiguityMargin: 0.04
      )
    }
  }
}

public struct GestureRecognizer: Sendable {
  public struct DistanceWeights: Hashable, Sendable {
    public let points: Float
    public let startDirection: Float
    public let endDirection: Float
    public let aspectRatio: Float

    public init(
      points: Float = 0.75,
      startDirection: Float = 0.1,
      endDirection: Float = 0.1,
      aspectRatio: Float = 0.05
    ) {
      self.points = max(0, points)
      self.startDirection = max(0, startDirection)
      self.endDirection = max(0, endDirection)
      self.aspectRatio = max(0, aspectRatio)
    }
  }

  public struct Configuration: Hashable, Sendable {
    public let acceptanceThreshold: Float
    public let ambiguityMargin: Float
    public let weights: DistanceWeights

    public init(
      acceptanceThreshold: Float = 0.35,
      ambiguityMargin: Float = 0.04,
      weights: DistanceWeights = DistanceWeights()
    ) {
      self.acceptanceThreshold = max(0, acceptanceThreshold)
      self.ambiguityMargin = max(0, ambiguityMargin)
      self.weights = weights
    }
  }

  public struct Match: Equatable, Sendable {
    public let request: ActionRequest
    public let distance: Float

    public init(
      request: ActionRequest,
      distance: Float
    ) {
      self.request = request
      self.distance = distance
    }

    public var mappingID: UUID { request.mappingID }
    public var action: GestureAction { request.action }
    public var shortcut: KeyboardShortcut {
      request.action.keyboardShortcut
        ?? ShortcutRecordingSession.emptyShortcut
    }
  }

  public enum Decision: Equatable, Sendable {
    case noMatch
    case ambiguous(bestDistance: Float, secondDistance: Float)
    case matched(Match)
  }

  private struct Candidate {
    let mapping: GestureMapping
    let distance: Float
    let specificity: Int
  }

  public let configuration: Configuration

  public init(configuration: Configuration = Configuration()) {
    self.configuration = configuration
  }

  public func recognize(
    _ gesture: GestureTemplate,
    mappings: [GestureMapping],
    frontmostBundleID: String?,
    inputDevice: GestureInputDevice? = nil,
    useSecondaryAction: Bool = false
  ) -> Decision {
    let candidates = mappings.compactMap { mapping -> Candidate? in
      guard mapping.isEnabled,
        mapping.action.isValid,
        mapping.appScope.includes(bundleID: frontmostBundleID),
        inputDevice.map(mapping.deviceScope.includes) ?? true
      else {
        return nil
      }

      let bestTemplateDistance = mapping.templates
        .lazy
        .map { distance(from: gesture, to: $0) }
        .filter(\.isFinite)
        .min()
      guard let bestTemplateDistance else {
        return nil
      }
      return Candidate(
        mapping: mapping,
        distance: bestTemplateDistance,
        specificity: specificity(
          of: mapping,
          for: frontmostBundleID,
          inputDevice: inputDevice
        )
      )
    }
    .sorted(by: candidatePrecedes)

    guard let nearest = candidates.first,
      nearest.distance <= configuration.acceptanceThreshold
    else {
      return .noMatch
    }

    let preferredSpecificity =
      candidates
      .filter {
        $0.distance <= configuration.acceptanceThreshold
          && ($0.distance == nearest.distance
            || $0.distance - nearest.distance
              < configuration.ambiguityMargin)
      }
      .map(\.specificity)
      .max() ?? nearest.specificity
    let preferredCandidates = candidates.filter {
      $0.specificity == preferredSpecificity
    }
    guard let best = preferredCandidates.first else {
      return .noMatch
    }

    if preferredCandidates.count > 1 {
      let second = preferredCandidates[1]
      let difference = second.distance - best.distance
      if difference > 0,
        difference < configuration.ambiguityMargin
      {
        return .ambiguous(
          bestDistance: best.distance,
          secondDistance: second.distance
        )
      }
    }

    return .matched(
      Match(
        request: ActionRequest(
          mappingID: best.mapping.id,
          mappingName: best.mapping.name,
          action:
            useSecondaryAction
            ? best.mapping.secondaryAction ?? .none
            : best.mapping.action,
          repeatModeEnabled: best.mapping.repeatModeEnabled
        ),
        distance: best.distance
      )
    )
  }

  private func specificity(
    of mapping: GestureMapping,
    for frontmostBundleID: String?,
    inputDevice: GestureInputDevice?
  ) -> Int {
    let applicationSpecificity: Int
    if mapping.appScope.isApplicationSpecific(
      for: frontmostBundleID
    ) {
      applicationSpecificity =
        mapping.applicationGroupID == nil ? 2 : 1
    } else {
      applicationSpecificity = 0
    }

    // Device scope remains the outer tie-breaker for near-identical gestures.
    let deviceSpecificity =
      inputDevice != nil && mapping.deviceScope.isDeviceSpecific
      ? 3 : 0
    return deviceSpecificity + applicationSpecificity
  }

  public func distance(
    from candidate: GestureTemplate,
    to template: GestureTemplate
  ) -> Float {
    guard candidate.points.count == template.points.count,
      !candidate.points.isEmpty
    else {
      return .infinity
    }

    let pointDistance = vectorDistance(
      candidate.points,
      template.points
    )
    let startDistance = directionDistance(
      candidate.startDirection,
      template.startDirection
    )
    let endDistance = directionDistance(
      candidate.endDirection,
      template.endDirection
    )
    let aspectDistance =
      abs(
        candidate.aspectRatio - template.aspectRatio
      ) / 2
    let weights = configuration.weights

    return (pointDistance * weights.points)
      + (startDistance * weights.startDirection)
      + (endDistance * weights.endDirection)
      + (aspectDistance * weights.aspectRatio)
  }

  private func candidatePrecedes(
    _ left: Candidate,
    _ right: Candidate
  ) -> Bool {
    if left.distance != right.distance {
      return left.distance < right.distance
    }
    if left.mapping.priority != right.mapping.priority {
      return left.mapping.priority < right.mapping.priority
    }
    return left.mapping.id.uuidString < right.mapping.id.uuidString
  }

  private func vectorDistance(
    _ left: [GesturePoint],
    _ right: [GesturePoint]
  ) -> Float {
    var dot: Float = 0
    var leftMagnitude: Float = 0
    var rightMagnitude: Float = 0

    for (leftPoint, rightPoint) in zip(left, right) {
      dot +=
        (leftPoint.x * rightPoint.x)
        + (leftPoint.y * rightPoint.y)
      leftMagnitude +=
        (leftPoint.x * leftPoint.x)
        + (leftPoint.y * leftPoint.y)
      rightMagnitude +=
        (rightPoint.x * rightPoint.x)
        + (rightPoint.y * rightPoint.y)
    }

    let denominator = sqrtf(leftMagnitude * rightMagnitude)
    guard denominator > Float.ulpOfOne else {
      return 1
    }
    let cosine = max(-1, min(1, dot / denominator))
    return acosf(cosine) / .pi
  }

  private func directionDistance(
    _ left: GesturePoint,
    _ right: GesturePoint
  ) -> Float {
    let dot = max(-1, min(1, (left.x * right.x) + (left.y * right.y)))
    return (1 - dot) / 2
  }
}
