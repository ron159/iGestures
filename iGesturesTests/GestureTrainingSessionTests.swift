import XCTest

@testable import iGestures

final class GestureTrainingSessionTests: XCTestCase {
  func testThreeConsistentSamplesAndTwoTestsBecomeReady() {
    var session = GestureTrainingSession(existingMappings: [])

    XCTAssertEqual(
      session.recordSample(line(angle: 0, offset: 0)),
      .sampleAccepted(count: 1, required: 3)
    )
    XCTAssertEqual(
      session.recordSample(line(angle: 0, offset: 50)),
      .sampleAccepted(count: 2, required: 3)
    )
    XCTAssertEqual(
      session.recordSample(line(angle: 0, offset: 100)),
      .readyForTesting(requiredSuccessfulTests: 2)
    )
    XCTAssertEqual(
      session.recordTest(line(angle: 0.01, offset: 0)),
      .testAccepted(count: 1, required: 2)
    )
    XCTAssertEqual(
      session.recordTest(line(angle: -0.01, offset: 0)),
      .readyToSave
    )
    XCTAssertEqual(session.phase, .readyToSave)
    XCTAssertEqual(session.templates.count, 3)
  }

  func testInconsistentSampleIsRejected() {
    var session = GestureTrainingSession(existingMappings: [])
    _ = session.recordSample(line(angle: 0, offset: 0))

    let result = session.recordSample(
      line(angle: .pi / 2, offset: 0)
    )

    guard case .sampleRejected(.inconsistent) = result else {
      return XCTFail("Expected an inconsistent sample, got \(result)")
    }
    XCTAssertEqual(session.templates.count, 1)
  }

  func testConflictWithExistingMappingIsRejected() throws {
    let existingID = UUID()
    let existing = GestureMapping(
      id: existingID,
      name: "Existing",
      templates: [try normalized(angle: 0)],
      shortcut: KeyboardShortcut(keyCode: 12, modifiers: 0)
    )
    var session = GestureTrainingSession(
      existingMappings: [existing]
    )

    let result = session.recordSample(line(angle: 0, offset: 20))

    guard
      case .sampleRejected(
        .conflicts(let mappingID, _)
      ) = result
    else {
      return XCTFail("Expected a conflict, got \(result)")
    }
    XCTAssertEqual(mappingID, existingID)
  }

  func testEditingMappingDoesNotConflictWithItself() throws {
    let existingID = UUID()
    let existing = GestureMapping(
      id: existingID,
      name: "Existing",
      templates: [try normalized(angle: 0)],
      shortcut: KeyboardShortcut(keyCode: 12, modifiers: 0)
    )
    var session = GestureTrainingSession(
      existingMappings: [existing],
      editingMappingID: existingID
    )

    XCTAssertEqual(
      session.recordSample(line(angle: 0, offset: 20)),
      .sampleAccepted(count: 1, required: 3)
    )
  }

  func testApplicationSpecificMappingCanOverrideGlobalGesture()
    throws
  {
    let existing = GestureMapping(
      name: "Global",
      templates: [try normalized(angle: 0)],
      shortcut: KeyboardShortcut(keyCode: 12, modifiers: 0),
      appScope: .all
    )
    var session = GestureTrainingSession(
      existingMappings: [existing],
      appScope: .only(["com.apple.Safari"])
    )

    XCTAssertEqual(
      session.recordSample(line(angle: 0, offset: 20)),
      .sampleAccepted(count: 1, required: 3)
    )
  }

  func testOverlappingApplicationSpecificGestureConflicts()
    throws
  {
    let existingID = UUID()
    let existing = GestureMapping(
      id: existingID,
      name: "Safari",
      templates: [try normalized(angle: 0)],
      shortcut: KeyboardShortcut(keyCode: 12, modifiers: 0),
      appScope: .only(["com.apple.Safari"])
    )
    var session = GestureTrainingSession(
      existingMappings: [existing],
      appScope: .only(["com.apple.Safari", "com.apple.finder"])
    )

    let result = session.recordSample(line(angle: 0, offset: 20))
    guard case .sampleRejected(.conflicts(let id, _)) = result else {
      return XCTFail("Expected a conflict, got \(result)")
    }
    XCTAssertEqual(id, existingID)
  }

  func testDirectApplicationGestureCanOverrideGroupGesture()
    throws
  {
    let existing = GestureMapping(
      name: "Browser Group",
      templates: [try normalized(angle: 0)],
      shortcut: KeyboardShortcut(keyCode: 12, modifiers: 0),
      appScope: .only(["com.apple.Safari"]),
      applicationGroupID: UUID()
    )
    var session = GestureTrainingSession(
      existingMappings: [existing],
      appScope: .only(["com.apple.Safari"])
    )

    XCTAssertEqual(
      session.recordSample(line(angle: 0, offset: 20)),
      .sampleAccepted(count: 1, required: 3)
    )
  }

  func testAdditionalSamplesAreCapped() {
    var session = GestureTrainingSession(
      existingMappings: [],
      configuration: .init(
        requiredSampleCount: 1,
        maximumSampleCount: 2
      )
    )
    _ = session.recordSample(line(angle: 0, offset: 0))

    XCTAssertEqual(
      session.recordAdditionalSample(line(angle: 0, offset: 20)),
      .readyForTesting(requiredSuccessfulTests: 2)
    )
    XCTAssertEqual(
      session.recordAdditionalSample(line(angle: 0, offset: 40)),
      .invalidPhase
    )
  }

  private func normalized(angle: Float) throws -> GestureTemplate {
    try GestureNormalizer().normalize(
      line(angle: angle, offset: 0)
    )
  }

  private func line(
    angle: Float,
    offset: Float
  ) -> [GesturePoint] {
    (0..<80).map { index in
      let distance = Float(index) * 2
      return GesturePoint(
        x: offset + (cosf(angle) * distance),
        y: offset + (sinf(angle) * distance)
      )
    }
  }
}
