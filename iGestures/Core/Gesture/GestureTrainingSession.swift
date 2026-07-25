import Foundation

public enum GestureTrainingPhase: Equatable, Sendable {
  case collecting(sampleCount: Int)
  case testing(successCount: Int)
  case readyToSave
}

public enum GestureTrainingIssue: Equatable, Sendable {
  case invalidStroke(GestureNormalizer.NormalizationError)
  case inconsistent(distance: Float)
  case conflicts(mappingID: UUID, distance: Float)
}

public enum GestureTrainingResult: Equatable, Sendable {
  case sampleAccepted(count: Int, required: Int)
  case sampleRejected(GestureTrainingIssue)
  case readyForTesting(requiredSuccessfulTests: Int)
  case testAccepted(count: Int, required: Int)
  case testRejected(distance: Float)
  case readyToSave
  case invalidPhase
}

public struct GestureTrainingSession: Sendable {
  public struct Configuration: Equatable, Sendable {
    public let requiredSampleCount: Int
    public let maximumSampleCount: Int
    public let requiredSuccessfulTests: Int
    public let consistencyThreshold: Float
    public let conflictThreshold: Float

    public init(
      requiredSampleCount: Int = 3,
      maximumSampleCount: Int = 5,
      requiredSuccessfulTests: Int = 2,
      consistencyThreshold: Float = 0.18,
      conflictThreshold: Float = 0.12
    ) {
      let maximumSampleCount = max(1, maximumSampleCount)
      self.maximumSampleCount = maximumSampleCount
      self.requiredSampleCount = min(
        maximumSampleCount,
        max(1, requiredSampleCount)
      )
      self.requiredSuccessfulTests = max(1, requiredSuccessfulTests)
      self.consistencyThreshold = max(0, consistencyThreshold)
      self.conflictThreshold = max(0, conflictThreshold)
    }
  }

  public private(set) var phase: GestureTrainingPhase = .collecting(
    sampleCount: 0
  )
  public private(set) var templates: [GestureTemplate] = []
  public let configuration: Configuration

  private let existingMappings: [GestureMapping]
  private let editingMappingID: UUID?
  private let normalizer: GestureNormalizer
  private let recognizer: GestureRecognizer
  private var successfulTestCount = 0

  public init(
    existingMappings: [GestureMapping],
    editingMappingID: UUID? = nil,
    configuration: Configuration = Configuration(),
    normalizer: GestureNormalizer = GestureNormalizer(),
    recognizer: GestureRecognizer = GestureRecognizer()
  ) {
    self.existingMappings = existingMappings
    self.editingMappingID = editingMappingID
    self.configuration = configuration
    self.normalizer = normalizer
    self.recognizer = recognizer
  }

  @discardableResult
  public mutating func recordSample(
    _ points: [GesturePoint]
  ) -> GestureTrainingResult {
    guard case .collecting = phase else {
      return .invalidPhase
    }
    return acceptSample(points)
  }

  @discardableResult
  public mutating func recordAdditionalSample(
    _ points: [GesturePoint]
  ) -> GestureTrainingResult {
    guard case .testing = phase,
      templates.count < configuration.maximumSampleCount
    else {
      return .invalidPhase
    }
    successfulTestCount = 0
    return acceptSample(points, remainInTesting: true)
  }

  @discardableResult
  public mutating func recordTest(
    _ points: [GesturePoint]
  ) -> GestureTrainingResult {
    guard case .testing = phase else {
      return .invalidPhase
    }
    let candidate: GestureTemplate
    do {
      candidate = try normalizer.normalize(points)
    } catch let error as GestureNormalizer.NormalizationError {
      return .sampleRejected(.invalidStroke(error))
    } catch {
      return .invalidPhase
    }

    let bestDistance =
      templates
      .map { recognizer.distance(from: candidate, to: $0) }
      .min() ?? .infinity
    guard
      bestDistance
        <= recognizer.configuration.acceptanceThreshold
    else {
      return .testRejected(distance: bestDistance)
    }

    successfulTestCount += 1
    if successfulTestCount >= configuration.requiredSuccessfulTests {
      phase = .readyToSave
      return .readyToSave
    }
    phase = .testing(successCount: successfulTestCount)
    return .testAccepted(
      count: successfulTestCount,
      required: configuration.requiredSuccessfulTests
    )
  }

  public mutating func reset() {
    templates.removeAll(keepingCapacity: true)
    successfulTestCount = 0
    phase = .collecting(sampleCount: 0)
  }

  private mutating func acceptSample(
    _ points: [GesturePoint],
    remainInTesting: Bool = false
  ) -> GestureTrainingResult {
    let template: GestureTemplate
    do {
      template = try normalizer.normalize(points)
    } catch let error as GestureNormalizer.NormalizationError {
      return .sampleRejected(.invalidStroke(error))
    } catch {
      return .invalidPhase
    }

    if let consistencyDistance =
      templates
      .map({ recognizer.distance(from: template, to: $0) })
      .max(),
      consistencyDistance > configuration.consistencyThreshold
    {
      return .sampleRejected(
        .inconsistent(distance: consistencyDistance)
      )
    }

    if let conflict = closestConflict(to: template),
      conflict.distance < configuration.conflictThreshold
    {
      return .sampleRejected(
        .conflicts(
          mappingID: conflict.mappingID,
          distance: conflict.distance
        )
      )
    }

    templates.append(template)
    if remainInTesting {
      phase = .testing(successCount: 0)
      return .readyForTesting(
        requiredSuccessfulTests: configuration.requiredSuccessfulTests
      )
    }
    if templates.count >= configuration.requiredSampleCount {
      phase = .testing(successCount: 0)
      return .readyForTesting(
        requiredSuccessfulTests: configuration.requiredSuccessfulTests
      )
    }

    phase = .collecting(sampleCount: templates.count)
    return .sampleAccepted(
      count: templates.count,
      required: configuration.requiredSampleCount
    )
  }

  private func closestConflict(
    to template: GestureTemplate
  ) -> (mappingID: UUID, distance: Float)? {
    existingMappings
      .lazy
      .filter { $0.id != editingMappingID }
      .compactMap { mapping -> (UUID, Float)? in
        guard
          let distance = mapping.templates
            .map({
              recognizer.distance(from: template, to: $0)
            })
            .min()
        else {
          return nil
        }
        return (mapping.id, distance)
      }
      .min { $0.1 < $1.1 }
  }
}
