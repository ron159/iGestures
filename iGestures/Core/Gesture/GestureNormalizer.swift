import Foundation

public struct GestureNormalizer: Sendable {
  public struct Configuration: Hashable, Sendable {
    public let sampleCount: Int
    public let minimumPointDistance: Float
    public let minimumPathLength: Float
    public let maximumInputPointCount: Int
    public let directionSampleSpan: Int

    public init(
      sampleCount: Int = 64,
      minimumPointDistance: Float = 0.5,
      minimumPathLength: Float = 24,
      maximumInputPointCount: Int = 4_096,
      directionSampleSpan: Int = 8
    ) {
      self.sampleCount = max(2, sampleCount)
      self.minimumPointDistance = max(0, minimumPointDistance)
      self.minimumPathLength = max(0, minimumPathLength)
      self.maximumInputPointCount = max(2, maximumInputPointCount)
      self.directionSampleSpan = max(1, directionSampleSpan)
    }
  }

  public enum NormalizationError: Error, Equatable, Sendable {
    case insufficientPoints
    case tooManyPoints(limit: Int)
    case nonFinitePoint
    case pathTooShort(minimum: Float)
    case degeneratePath
  }

  public let configuration: Configuration

  public init(configuration: Configuration = Configuration()) {
    self.configuration = configuration
  }

  public func normalize(_ input: [GesturePoint]) throws -> GestureTemplate {
    guard input.count <= configuration.maximumInputPointCount else {
      throw NormalizationError.tooManyPoints(
        limit: configuration.maximumInputPointCount
      )
    }
    guard input.count >= 2 else {
      throw NormalizationError.insufficientPoints
    }
    guard input.allSatisfy(\.isFinite) else {
      throw NormalizationError.nonFinitePoint
    }

    let filtered = removeNearDuplicates(from: input)
    guard filtered.count >= 2 else {
      throw NormalizationError.insufficientPoints
    }

    let totalLength = pathLength(of: filtered)
    guard totalLength >= configuration.minimumPathLength else {
      throw NormalizationError.pathTooShort(
        minimum: configuration.minimumPathLength
      )
    }

    let resampled = resample(
      filtered,
      totalLength: totalLength,
      count: configuration.sampleCount
    )
    return try centerAndScale(resampled)
  }

  private func removeNearDuplicates(
    from points: [GesturePoint]
  ) -> [GesturePoint] {
    var result = [points[0]]
    result.reserveCapacity(points.count)

    for point in points.dropFirst()
    where result[result.count - 1].distance(to: point)
      >= configuration.minimumPointDistance
    {
      result.append(point)
    }

    if result[result.count - 1] != points[points.count - 1] {
      result.append(points[points.count - 1])
    }
    return result
  }

  private func pathLength(of points: [GesturePoint]) -> Float {
    zip(points, points.dropFirst()).reduce(into: 0) { length, pair in
      length += pair.0.distance(to: pair.1)
    }
  }

  private func resample(
    _ points: [GesturePoint],
    totalLength: Float,
    count: Int
  ) -> [GesturePoint] {
    let interval = totalLength / Float(count - 1)
    var result = [points[0]]
    result.reserveCapacity(count)

    var previous = points[0]
    var distanceSinceSample: Float = 0

    for endpoint in points.dropFirst() {
      var segmentLength = previous.distance(to: endpoint)

      while result.count < count - 1,
        segmentLength > Float.ulpOfOne,
        distanceSinceSample + segmentLength >= interval
      {
        let distanceToSample = interval - distanceSinceSample
        let sample = previous.interpolated(
          to: endpoint,
          fraction: distanceToSample / segmentLength
        )
        result.append(sample)
        previous = sample
        segmentLength = previous.distance(to: endpoint)
        distanceSinceSample = 0
      }

      distanceSinceSample += segmentLength
      previous = endpoint
    }

    while result.count < count {
      result.append(points[points.count - 1])
    }
    return result
  }

  private func centerAndScale(
    _ points: [GesturePoint]
  ) throws -> GestureTemplate {
    let count = Float(points.count)
    let centroid = points.reduce(
      into: GesturePoint(x: 0, y: 0)
    ) { partial, point in
      partial = GesturePoint(
        x: partial.x + point.x,
        y: partial.y + point.y
      )
    }
    let center = GesturePoint(
      x: centroid.x / count,
      y: centroid.y / count
    )

    let minX = points.map(\.x).min() ?? 0
    let maxX = points.map(\.x).max() ?? 0
    let minY = points.map(\.y).min() ?? 0
    let maxY = points.map(\.y).max() ?? 0
    let width = maxX - minX
    let height = maxY - minY
    let longestSide = max(width, height)
    guard longestSide > Float.ulpOfOne else {
      throw NormalizationError.degeneratePath
    }

    let normalizedPoints = points.map {
      GesturePoint(
        x: ($0.x - center.x) / longestSide,
        y: ($0.y - center.y) / longestSide
      )
    }
    let span = min(
      configuration.directionSampleSpan,
      normalizedPoints.count - 1
    )
    let startDirection = GesturePoint(
      x: normalizedPoints[span].x - normalizedPoints[0].x,
      y: normalizedPoints[span].y - normalizedPoints[0].y
    ).normalized()
    let endDirection = GesturePoint(
      x: normalizedPoints[normalizedPoints.count - 1].x
        - normalizedPoints[normalizedPoints.count - 1 - span].x,
      y: normalizedPoints[normalizedPoints.count - 1].y
        - normalizedPoints[normalizedPoints.count - 1 - span].y
    ).normalized()

    return GestureTemplate(
      points: normalizedPoints,
      aspectRatio: (width - height) / longestSide,
      startDirection: startDirection,
      endDirection: endDirection
    )
  }
}
