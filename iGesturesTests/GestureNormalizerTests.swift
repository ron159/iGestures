import XCTest

@testable import iGestures

final class GestureNormalizerTests: XCTestCase {
  func testPreviewLayoutKeepsGestureInsideSafeMargins() {
    let points = [
      GesturePoint(x: -0.5, y: -0.5),
      GesturePoint(x: 0, y: 0),
      GesturePoint(x: 0.5, y: 0.5),
    ]

    let compact = GesturePreviewLayout.scaledPoints(
      points,
      in: CGSize(width: 76, height: 54)
    )
    let large = GesturePreviewLayout.scaledPoints(
      points,
      in: CGSize(width: 190, height: 150)
    )

    XCTAssertGreaterThanOrEqual(compact.map(\.x).min() ?? 0, 7)
    XCTAssertLessThanOrEqual(compact.map(\.x).max() ?? 76, 69)
    XCTAssertGreaterThanOrEqual(compact.map(\.y).min() ?? 0, 7)
    XCTAssertLessThanOrEqual(compact.map(\.y).max() ?? 54, 47)

    XCTAssertGreaterThanOrEqual(large.map(\.x).min() ?? 0, 18)
    XCTAssertLessThanOrEqual(large.map(\.x).max() ?? 190, 172)
    XCTAssertGreaterThanOrEqual(large.map(\.y).min() ?? 0, 18)
    XCTAssertLessThanOrEqual(large.map(\.y).max() ?? 150, 132)
  }

  private let normalizer = GestureNormalizer()

  func testTranslationDoesNotChangeNormalizedGesture() throws {
    let original = line(from: (0, 0), to: (120, 40), count: 80)
    let translated = original.map {
      GesturePoint(x: $0.x + 400, y: $0.y - 250)
    }

    assertTemplatesEqual(
      try normalizer.normalize(original),
      try normalizer.normalize(translated)
    )
  }

  func testUniformScaleDoesNotChangeNormalizedGesture() throws {
    let original = chevron(scale: 1, samplesPerSegment: 40)
    let scaled = original.map {
      GesturePoint(x: $0.x * 3.5, y: $0.y * 3.5)
    }

    assertTemplatesEqual(
      try normalizer.normalize(original),
      try normalizer.normalize(scaled)
    )
  }

  func testSamplingDensityDoesNotChangeNormalizedGesture() throws {
    let sparse = chevron(scale: 1, samplesPerSegment: 12)
    let dense = chevron(scale: 1, samplesPerSegment: 120)

    assertTemplatesEqual(
      try normalizer.normalize(sparse),
      try normalizer.normalize(dense),
      accuracy: 0.01
    )
  }

  func testDrawingSpeedDoesNotChangeNormalizedGesture() throws {
    let uniform = chevronByProgress(
      count: 120,
      progress: { $0 }
    )
    let variableSpeed = chevronByProgress(
      count: 120,
      progress: { powf($0, 3) }
    )

    assertTemplatesEqual(
      try normalizer.normalize(uniform),
      try normalizer.normalize(variableSpeed),
      accuracy: 0.01
    )
  }

  func testSmallDeterministicNoiseRemainsRecognizable() throws {
    let original = chevron(scale: 1, samplesPerSegment: 60)
    let noisy = original.enumerated().map { index, point in
      GesturePoint(
        x: point.x + (sinf(Float(index) * 1.7) * 1.2),
        y: point.y + (cosf(Float(index) * 1.3) * 1.2)
      )
    }
    let distance = GestureRecognizer().distance(
      from: try normalizer.normalize(original),
      to: try normalizer.normalize(noisy)
    )

    XCTAssertLessThan(distance, 0.08)
  }

  func testHorizontalAndVerticalLinesRemainFinite() throws {
    let horizontal = try normalizer.normalize(
      line(from: (0, 0), to: (120, 0), count: 80)
    )
    let vertical = try normalizer.normalize(
      line(from: (0, 0), to: (0, 120), count: 80)
    )

    XCTAssertTrue(horizontal.points.allSatisfy(\.isFinite))
    XCTAssertTrue(vertical.points.allSatisfy(\.isFinite))
    XCTAssertTrue(horizontal.aspectRatio.isFinite)
    XCTAssertTrue(vertical.aspectRatio.isFinite)
    XCTAssertGreaterThan(
      GestureRecognizer().distance(from: horizontal, to: vertical),
      0.1
    )
  }

  func testRotationAndReverseDirectionRemainDistinct() throws {
    let right = try normalizer.normalize(
      line(from: (0, 0), to: (120, 0), count: 80)
    )
    let up = try normalizer.normalize(
      line(from: (0, 0), to: (0, 120), count: 80)
    )
    let left = try normalizer.normalize(
      line(from: (120, 0), to: (0, 0), count: 80)
    )
    let recognizer = GestureRecognizer()

    XCTAssertGreaterThan(
      recognizer.distance(from: right, to: up),
      0.1
    )
    XCTAssertGreaterThan(
      recognizer.distance(from: right, to: left),
      0.1
    )
  }

  func testInvalidInputIsRejected() {
    XCTAssertThrowsError(try normalizer.normalize([]))
    XCTAssertThrowsError(
      try normalizer.normalize([GesturePoint(x: 0, y: 0)])
    )
    XCTAssertThrowsError(
      try normalizer.normalize([
        GesturePoint(x: .nan, y: 0),
        GesturePoint(x: 100, y: 0),
      ])
    )

    let limited = GestureNormalizer(
      configuration: .init(maximumInputPointCount: 3)
    )
    XCTAssertThrowsError(
      try limited.normalize(
        line(from: (0, 0), to: (120, 0), count: 4)
      )
    )
  }

  private func assertTemplatesEqual(
    _ left: GestureTemplate,
    _ right: GestureTemplate,
    accuracy: Float = 0.0001,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(left.points.count, right.points.count, file: file, line: line)
    for (leftPoint, rightPoint) in zip(left.points, right.points) {
      XCTAssertEqual(leftPoint.x, rightPoint.x, accuracy: accuracy, file: file, line: line)
      XCTAssertEqual(leftPoint.y, rightPoint.y, accuracy: accuracy, file: file, line: line)
    }
    XCTAssertEqual(left.aspectRatio, right.aspectRatio, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(
      left.startDirection.x, right.startDirection.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(
      left.startDirection.y, right.startDirection.y, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(
      left.endDirection.x, right.endDirection.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(
      left.endDirection.y, right.endDirection.y, accuracy: accuracy, file: file, line: line)
  }

  private func line(
    from start: (Float, Float),
    to end: (Float, Float),
    count: Int
  ) -> [GesturePoint] {
    (0..<count).map { index in
      let fraction = Float(index) / Float(count - 1)
      return GesturePoint(
        x: start.0 + ((end.0 - start.0) * fraction),
        y: start.1 + ((end.1 - start.1) * fraction)
      )
    }
  }

  private func chevron(
    scale: Float,
    samplesPerSegment: Int
  ) -> [GesturePoint] {
    let first = line(
      from: (0, 80 * scale),
      to: (60 * scale, 0),
      count: samplesPerSegment
    )
    let second = line(
      from: (60 * scale, 0),
      to: (120 * scale, 80 * scale),
      count: samplesPerSegment
    )
    return first + second.dropFirst()
  }

  private func chevronByProgress(
    count: Int,
    progress: (Float) -> Float
  ) -> [GesturePoint] {
    (0..<count).map { index in
      let linear = Float(index) / Float(count - 1)
      let value = min(1, max(0, progress(linear)))
      if value <= 0.5 {
        return GesturePoint(
          x: value * 120,
          y: 80 - (value * 160)
        )
      }
      return GesturePoint(
        x: value * 120,
        y: (value - 0.5) * 160
      )
    }
  }
}
