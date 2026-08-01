import XCTest

@testable import iGestures

final class GestureRecognizerTests: XCTestCase {
  private let normalizer = GestureNormalizer()
  private let shortcut = KeyboardShortcut(keyCode: 1, modifiers: 1 << 20)

  func testNearestTemplateWins() throws {
    let horizontal = try template(angle: 0)
    let vertical = try template(angle: .pi / 2)
    let horizontalID = UUID()
    let mappings = [
      mapping(id: verticalID, template: vertical, priority: 0),
      mapping(id: horizontalID, template: horizontal, priority: 1),
    ]

    let decision = GestureRecognizer().recognize(
      horizontal,
      mappings: mappings,
      frontmostBundleID: "com.apple.finder"
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected a match, got \(decision)")
    }
    XCTAssertEqual(match.mappingID, horizontalID)
    XCTAssertEqual(match.distance, 0, accuracy: 0.0001)
  }

  func testApplicationScopeFiltersMappings() throws {
    let candidate = try template(angle: 0)
    let finderOnlyID = UUID()
    let globalID = UUID()
    let mappings = [
      mapping(
        id: finderOnlyID,
        template: candidate,
        scope: .only(["com.apple.finder"]),
        priority: 0
      ),
      mapping(
        id: globalID,
        template: try template(angle: 0.2),
        scope: .all,
        priority: 1
      ),
    ]

    let decision = GestureRecognizer().recognize(
      candidate,
      mappings: mappings,
      frontmostBundleID: "com.apple.Safari"
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected a match, got \(decision)")
    }
    XCTAssertEqual(match.mappingID, globalID)
  }

  func testApplicationSpecificLayerWinsWhenDistancesAreClose()
    throws
  {
    let candidate = try template(angle: 0)
    let specificTemplate = try template(angle: 0.12)
    let specificID = UUID()
    let globalID = UUID()
    let recognizer = GestureRecognizer()
    let mappings = [
      mapping(
        id: globalID,
        template: candidate,
        scope: .all,
        priority: 0
      ),
      mapping(
        id: specificID,
        template: specificTemplate,
        scope: .only(["com.apple.Safari"]),
        priority: 1
      ),
    ]

    XCTAssertLessThan(
      recognizer.distance(from: candidate, to: specificTemplate),
      recognizer.configuration.ambiguityMargin
    )

    let decision = recognizer.recognize(
      candidate,
      mappings: mappings,
      frontmostBundleID: "com.apple.Safari"
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected a match, got \(decision)")
    }
    XCTAssertEqual(match.mappingID, specificID)
  }

  func testClearlyCloserGlobalMappingBeatsRecognizableGroupMapping()
    throws
  {
    let candidate = try template(angle: 0)
    let groupTemplate = try template(angle: 0.8)
    let globalID = UUID()
    let recognizer = GestureRecognizer()
    let groupDistance = recognizer.distance(
      from: candidate,
      to: groupTemplate
    )

    XCTAssertGreaterThan(
      groupDistance,
      recognizer.configuration.ambiguityMargin
    )
    XCTAssertLessThan(
      groupDistance,
      recognizer.configuration.acceptanceThreshold
    )

    let decision = recognizer.recognize(
      candidate,
      mappings: [
        mapping(
          id: UUID(),
          template: groupTemplate,
          scope: .only(["com.microsoft.edgemac"]),
          applicationGroupID: UUID()
        ),
        mapping(
          id: globalID,
          template: candidate,
          scope: .all
        ),
      ],
      frontmostBundleID: "com.microsoft.edgemac"
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected the clearly closer global match")
    }
    XCTAssertEqual(match.mappingID, globalID)
  }

  func testClearlyCloserGlobalMappingBeatsRecognizableDirectMapping()
    throws
  {
    let candidate = try template(angle: 0)
    let directTemplate = try template(angle: 0.8)
    let globalID = UUID()
    let recognizer = GestureRecognizer()
    let directDistance = recognizer.distance(
      from: candidate,
      to: directTemplate
    )

    XCTAssertGreaterThan(
      directDistance,
      recognizer.configuration.ambiguityMargin
    )
    XCTAssertLessThan(
      directDistance,
      recognizer.configuration.acceptanceThreshold
    )

    let decision = recognizer.recognize(
      candidate,
      mappings: [
        mapping(
          id: UUID(),
          template: directTemplate,
          scope: .only(["com.microsoft.edgemac"])
        ),
        mapping(id: globalID, template: candidate),
      ],
      frontmostBundleID: "com.microsoft.edgemac"
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected the clearly closer global match")
    }
    XCTAssertEqual(match.mappingID, globalID)
  }

  func testGroupAmbiguityDoesNotBlockClearlyCloserGlobalMapping()
    throws
  {
    let candidate = try template(angle: 0)
    let firstGroupTemplate = try template(angle: 0.8)
    let secondGroupTemplate = try template(angle: 0.82)
    let globalID = UUID()
    let recognizer = GestureRecognizer()
    let groupDistances = [firstGroupTemplate, secondGroupTemplate].map {
      recognizer.distance(from: candidate, to: $0)
    }

    XCTAssertTrue(
      groupDistances.allSatisfy {
        $0 < recognizer.configuration.acceptanceThreshold
      }
    )
    XCTAssertLessThan(
      abs(groupDistances[0] - groupDistances[1]),
      recognizer.configuration.ambiguityMargin
    )
    XCTAssertGreaterThan(
      groupDistances.min() ?? 0,
      recognizer.configuration.ambiguityMargin
    )

    let decision = recognizer.recognize(
      candidate,
      mappings: [
        mapping(
          id: UUID(),
          template: firstGroupTemplate,
          scope: .only(["com.microsoft.edgemac"]),
          applicationGroupID: UUID()
        ),
        mapping(
          id: UUID(),
          template: secondGroupTemplate,
          scope: .only(["com.microsoft.edgemac"]),
          applicationGroupID: UUID()
        ),
        mapping(id: globalID, template: candidate),
      ],
      frontmostBundleID: "com.microsoft.edgemac"
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected the clearly closer global match")
    }
    XCTAssertEqual(match.mappingID, globalID)
  }

  func testApplicationSpecificNoMatchFallsBackToGlobal() throws {
    let candidate = try template(angle: 0)
    let globalID = UUID()
    let mappings = [
      mapping(
        id: UUID(),
        template: try template(angle: .pi / 2),
        scope: .only(["com.apple.Safari"])
      ),
      mapping(
        id: globalID,
        template: candidate,
        scope: .all
      ),
    ]

    let decision = GestureRecognizer().recognize(
      candidate,
      mappings: mappings,
      frontmostBundleID: "com.apple.Safari"
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected global fallback, got \(decision)")
    }
    XCTAssertEqual(match.mappingID, globalID)
  }

  func testDirectApplicationMappingOverridesGroupMapping() throws {
    let candidate = try template(angle: 0)
    let directID = UUID()
    let groupID = UUID()
    let decision = GestureRecognizer().recognize(
      candidate,
      mappings: [
        mapping(
          id: groupID,
          template: candidate,
          scope: .only(["com.apple.Safari"]),
          applicationGroupID: UUID()
        ),
        mapping(
          id: directID,
          template: try template(angle: 0.12),
          scope: .only(["com.apple.Safari"])
        ),
      ],
      frontmostBundleID: "com.apple.Safari"
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected a direct application match")
    }
    XCTAssertEqual(match.mappingID, directID)
  }

  func testGroupMappingFallsBackToGlobalMapping() throws {
    let candidate = try template(angle: 0)
    let globalID = UUID()
    let decision = GestureRecognizer().recognize(
      candidate,
      mappings: [
        mapping(
          id: UUID(),
          template: try template(angle: .pi / 2),
          scope: .only(["com.apple.Safari"]),
          applicationGroupID: UUID()
        ),
        mapping(
          id: globalID,
          template: candidate
        ),
      ],
      frontmostBundleID: "com.apple.Safari"
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected a global fallback")
    }
    XCTAssertEqual(match.mappingID, globalID)
  }

  func testSimilarMappingsInSameSpecificLayerAreAmbiguous()
    throws
  {
    let candidate = try template(angle: 0)
    let recognizer = GestureRecognizer(
      configuration: .init(
        acceptanceThreshold: 1,
        ambiguityMargin: 1
      )
    )
    let decision = recognizer.recognize(
      candidate,
      mappings: [
        mapping(
          id: UUID(),
          template: try template(angle: 0.01),
          scope: .only(["com.apple.Safari"])
        ),
        mapping(
          id: UUID(),
          template: try template(angle: 0.02),
          scope: .only(["com.apple.Safari"])
        ),
      ],
      frontmostBundleID: "com.apple.Safari"
    )

    guard case .ambiguous = decision else {
      return XCTFail("Expected ambiguity, got \(decision)")
    }
  }

  func testTrackpadSpecificFlowOverridesDeviceAgnosticFlow()
    throws
  {
    let candidate = try template(angle: 0)
    let anyDeviceID = UUID()
    let trackpadID = UUID()
    let decision = GestureRecognizer().recognize(
      candidate,
      mappings: [
        mapping(
          id: anyDeviceID,
          template: candidate,
          deviceScope: .any
        ),
        mapping(
          id: trackpadID,
          template: try template(angle: 0.1),
          deviceScope: .trackpad
        ),
      ],
      frontmostBundleID: nil,
      inputDevice: .trackpad
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected a trackpad match, got \(decision)")
    }
    XCTAssertEqual(match.mappingID, trackpadID)
  }

  func testClearlyCloserDeviceAgnosticFlowBeatsTrackpadFlow()
    throws
  {
    let candidate = try template(angle: 0)
    let anyDeviceID = UUID()
    let recognizer = GestureRecognizer()
    let trackpadTemplate = try template(angle: 0.8)

    XCTAssertGreaterThan(
      recognizer.distance(from: candidate, to: trackpadTemplate),
      recognizer.configuration.ambiguityMargin
    )

    let decision = recognizer.recognize(
      candidate,
      mappings: [
        mapping(
          id: anyDeviceID,
          template: candidate,
          deviceScope: .any
        ),
        mapping(
          id: UUID(),
          template: trackpadTemplate,
          deviceScope: .trackpad
        ),
      ],
      frontmostBundleID: nil,
      inputDevice: .trackpad
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected the clearly closer device-agnostic match")
    }
    XCTAssertEqual(match.mappingID, anyDeviceID)
  }

  func testMouseFlowDoesNotConsumeTrackpadInput() throws {
    let candidate = try template(angle: 0)
    let decision = GestureRecognizer().recognize(
      candidate,
      mappings: [
        mapping(
          id: UUID(),
          template: candidate,
          deviceScope: .mouse(identifier: nil)
        )
      ],
      frontmostBundleID: nil,
      inputDevice: .trackpad
    )

    XCTAssertEqual(decision, .noMatch)
  }

  func testAllExceptScopeFailsClosedForExcludedOrUnknownApp()
    throws
  {
    let candidate = try template(angle: 0)
    let mapping = mapping(
      id: UUID(),
      template: candidate,
      scope: .allExcept(["com.apple.Safari"])
    )
    let recognizer = GestureRecognizer()

    XCTAssertEqual(
      recognizer.recognize(
        candidate,
        mappings: [mapping],
        frontmostBundleID: "com.apple.Safari"
      ),
      .noMatch
    )
    XCTAssertEqual(
      recognizer.recognize(
        candidate,
        mappings: [mapping],
        frontmostBundleID: nil
      ),
      .noMatch
    )
    guard
      case .matched = recognizer.recognize(
        candidate,
        mappings: [mapping],
        frontmostBundleID: "com.apple.finder"
      )
    else {
      return XCTFail("Expected a non-excluded app to match")
    }
  }

  func testThresholdRejectsDistantTemplate() throws {
    let recognizer = GestureRecognizer(
      configuration: .init(acceptanceThreshold: 0.01)
    )
    let decision = recognizer.recognize(
      try template(angle: 0),
      mappings: [
        mapping(
          id: UUID(),
          template: try template(angle: .pi / 2)
        )
      ],
      frontmostBundleID: nil
    )

    XCTAssertEqual(decision, .noMatch)
  }

  func testCloseSecondCandidateIsAmbiguous() throws {
    let recognizer = GestureRecognizer(
      configuration: .init(
        acceptanceThreshold: 1,
        ambiguityMargin: 1
      )
    )
    let decision = recognizer.recognize(
      try template(angle: 0),
      mappings: [
        mapping(
          id: UUID(),
          template: try template(angle: 0.1)
        ),
        mapping(
          id: UUID(),
          template: try template(angle: .pi / 2)
        ),
      ],
      frontmostBundleID: nil
    )

    guard case .ambiguous = decision else {
      return XCTFail("Expected ambiguity, got \(decision)")
    }
  }

  func testPriorityResolvesExactlyEqualDistance() throws {
    let candidate = try template(angle: 0)
    let preferredID = UUID()
    let mappings = [
      mapping(id: UUID(), template: candidate, priority: 10),
      mapping(id: preferredID, template: candidate, priority: 2),
    ]

    let decision = GestureRecognizer().recognize(
      candidate,
      mappings: mappings,
      frontmostBundleID: nil
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected a match, got \(decision)")
    }
    XCTAssertEqual(match.mappingID, preferredID)
  }

  func testSecondaryTriggerSelectsHigherPriorityAction() throws {
    let candidate = try template(angle: 0)
    var mapping = mapping(
      id: UUID(),
      template: candidate
    )
    mapping.secondaryAction = .window(.maximize)

    let decision = GestureRecognizer().recognize(
      candidate,
      mappings: [mapping],
      frontmostBundleID: nil,
      useSecondaryAction: true
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected a match, got \(decision)")
    }
    XCTAssertEqual(match.action, .window(.maximize))
  }

  func testMissingSecondaryActionDoesNotFallBackToPrimaryAction() throws {
    let candidate = try template(angle: 0)
    let mapping = mapping(
      id: UUID(),
      template: candidate
    )

    let decision = GestureRecognizer().recognize(
      candidate,
      mappings: [mapping],
      frontmostBundleID: nil,
      useSecondaryAction: true
    )

    guard case .matched(let match) = decision else {
      return XCTFail("Expected a match, got \(decision)")
    }
    XCTAssertEqual(match.action, .none)
  }

  func testPrimaryAndSecondaryActionsCanBeSelectedIndependently() throws {
    let candidate = try template(angle: 0)
    var mapping = mapping(
      id: UUID(),
      template: candidate
    )
    mapping.action = .none
    mapping.secondaryAction = .window(.maximize)

    let primaryDecision = GestureRecognizer().recognize(
      candidate,
      mappings: [mapping],
      frontmostBundleID: nil
    )
    let secondaryDecision = GestureRecognizer().recognize(
      candidate,
      mappings: [mapping],
      frontmostBundleID: nil,
      useSecondaryAction: true
    )

    guard case .matched(let primaryMatch) = primaryDecision,
      case .matched(let secondaryMatch) = secondaryDecision
    else {
      return XCTFail("Expected both trigger modes to match")
    }
    XCTAssertEqual(primaryMatch.action, .none)
    XCTAssertEqual(secondaryMatch.action, .window(.maximize))
  }

  func testDisabledAndInvalidMappingsDoNotParticipate() throws {
    let candidate = try template(angle: 0)
    let disabled = GestureMapping(
      name: "Disabled",
      isEnabled: false,
      templates: [candidate],
      shortcut: shortcut,
      appScope: .all,
      priority: 0
    )
    let invalidShortcut = GestureMapping(
      name: "Invalid",
      templates: [candidate],
      shortcut: KeyboardShortcut(
        keyCode: .max,
        modifiers: 0
      ),
      appScope: .all,
      priority: 0
    )

    XCTAssertEqual(
      GestureRecognizer().recognize(
        candidate,
        mappings: [disabled, invalidShortcut],
        frontmostBundleID: nil
      ),
      .noMatch
    )
  }

  func testHundredMappingsWithThreeTemplatesRemainBounded() throws {
    let candidate = try template(angle: 0)
    let mappings = try (0..<100).map { index in
      GestureMapping(
        name: "Gesture \(index)",
        templates: [
          try template(angle: Float(index) * 0.01),
          try template(angle: Float(index) * 0.01 + 0.02),
          try template(angle: Float(index) * 0.01 - 0.02),
        ],
        shortcut: shortcut,
        appScope: .all,
        priority: index
      )
    }
    let recognizer = GestureRecognizer()
    _ = recognizer.recognize(
      candidate,
      mappings: mappings,
      frontmostBundleID: nil
    )
    var samples: [Duration] = []
    samples.reserveCapacity(100)
    for _ in 0..<100 {
      let start = ContinuousClock.now
      _ = recognizer.recognize(
        candidate,
        mappings: mappings,
        frontmostBundleID: nil
      )
      samples.append(ContinuousClock.now - start)
    }

    #if DEBUG
      let maximumP95 = Duration.milliseconds(30)
    #else
      let maximumP95 = Duration.milliseconds(2)
    #endif
    XCTAssertLessThan(
      samples.sorted()[94],
      maximumP95
    )
  }

  private var verticalID: UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  }

  private func mapping(
    id: UUID,
    template: GestureTemplate,
    scope: AppScope = .all,
    priority: Int = 0,
    applicationGroupID: UUID? = nil,
    deviceScope: InputDeviceScope = .any
  ) -> GestureMapping {
    GestureMapping(
      id: id,
      name: "Test",
      templates: [template],
      shortcut: shortcut,
      appScope: scope,
      applicationGroupID: applicationGroupID,
      deviceScope: deviceScope,
      priority: priority
    )
  }

  private func template(angle: Float) throws -> GestureTemplate {
    let cosine = cosf(angle)
    let sine = sinf(angle)
    let points = (0..<80).map { index in
      let distance = Float(index) * 2
      return GesturePoint(
        x: cosine * distance,
        y: sine * distance
      )
    }
    return try normalizer.normalize(points)
  }
}
