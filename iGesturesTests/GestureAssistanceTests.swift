import XCTest

@testable import iGestures

final class GestureAssistanceTests: XCTestCase {
  private let safari = "com.apple.Safari"
  private let action = GestureAction.keyboardShortcut(
    KeyboardShortcut(keyCode: 13, modifiers: 1 << 20))

  private func stroke(_ angle: Float = 0) -> [GesturePoint] {
    (0..<80).map { GesturePoint(x: Float($0) * 2 * cosf(angle), y: Float($0) * 2 * sinf(angle)) }
  }

  private func mapping(_ name: String, angle: Float = 0, scope: AppScope = .all) throws
    -> GestureMapping
  {
    GestureMapping(
      name: name, templates: [try GestureNormalizer().normalize(stroke(angle))], action: action,
      appScope: scope)
  }

  private func diagnose(
    _ mappings: [GestureMapping], angle: Float = 0,
    context: GestureMatchContext = GestureMatchContext()
  ) -> GestureDiagnosticDetail {
    GestureAssistance.diagnose(
      stroke(angle), snapshot: CompiledMappingSnapshot(mappings: mappings), bundleID: safari,
      trigger: .right, defaultTrigger: .right, context: context)
  }

  func testPracticeUsesTheSameApplicationWinnerAsExecution() throws {
    let global = try mapping("Global")
    let app = try mapping("Safari", scope: .only([safari]))
    let result = diagnose([global, app])
    XCTAssertEqual(result.reason, .matched)
    XCTAssertEqual(result.suggestions.map(\.mappingID), [app.id])
  }

  func testDiagnosticExplainsScopeTriggerAndConditionFailures() throws {
    var other = try mapping("Finder", scope: .only(["com.apple.finder"]))
    XCTAssertEqual(diagnose([other]).reason, .applicationScope)
    other.appScope = .all
    other.triggerButton = .middle
    XCTAssertEqual(diagnose([other]).reason, .trigger)
    other.triggerButton = nil
    other.contextCondition = GestureContextCondition(requiredModifiers: 1 << 20)
    XCTAssertEqual(diagnose([other]).reason, .conditions)
    XCTAssertEqual(
      diagnose([other], context: GestureMatchContext(modifierFlags: 1 << 20)).reason, .matched)
  }

  func testDiagnosticNamesTheActualAmbiguousApplicationRules() throws {
    let global = try mapping("Global", angle: 0.08)
    let first = try mapping("First", angle: 0.07, scope: .only([safari]))
    let second = try mapping("Second", angle: 0.12, scope: .only([safari]))
    let result = diagnose([global, first, second], angle: 0.08)
    XCTAssertEqual(result.reason, .ambiguous)
    XCTAssertEqual(Set(result.suggestions.map(\.mappingID)), [first.id, second.id])
  }

  func testAnUnrelatedBlockedRuleDoesNotExplainANoMatch() throws {
    let other = try mapping("Finder", angle: .pi, scope: .only(["com.apple.finder"]))
    let result = diagnose([other])
    XCTAssertEqual(result.reason, .noMatch)
    XCTAssertTrue(result.suggestions.isEmpty)
  }

  func testShortAndInvalidStrokesHaveDistinctReasons() {
    let snapshot = CompiledMappingSnapshot.empty
    let short = GestureAssistance.diagnose(
      [GesturePoint(x: 0, y: 0), GesturePoint(x: 1, y: 1)],
      snapshot: snapshot, bundleID: safari, trigger: .right, defaultTrigger: .right)
    XCTAssertEqual(short.reason, .strokeTooShort)
    let invalid = GestureAssistance.diagnose(
      [GesturePoint(x: .nan, y: 0), GesturePoint(x: 100, y: 100)],
      snapshot: snapshot, bundleID: safari, trigger: .right, defaultTrigger: .right)
    XCTAssertEqual(invalid.reason, .invalidStroke)
  }

  func testReferenceExplainsOverrideAndKeepsUnrelatedGlobals() throws {
    let global = try mapping("Global")
    let otherGlobal = try mapping("Other Global", angle: .pi / 2)
    let app = try mapping("Safari", scope: .only([safari]))
    let entries = GestureAssistance.reference(
      snapshot: CompiledMappingSnapshot(mappings: [global, otherGlobal, app]),
      bundleID: safari, defaultTrigger: .right)
    XCTAssertEqual(entries.first { $0.id == global.id }?.overriddenBy?.mappingID, app.id)
    XCTAssertNil(entries.first { $0.id == otherGlobal.id }?.overriddenBy)
    XCTAssertNil(entries.first { $0.id == app.id }?.overriddenBy)
  }

  func testReferenceFiltersDisabledAndExcludedRulesAndMarksConditions() throws {
    var disabled = try mapping("Disabled")
    disabled.isEnabled = false
    var middle = try mapping("Middle")
    middle.triggerButton = .middle
    var conditional = try mapping("Conditional")
    conditional.requiredChordButtons = [.left]
    let entries = GestureAssistance.reference(
      snapshot: CompiledMappingSnapshot(mappings: [disabled, middle, conditional]),
      bundleID: safari, defaultTrigger: .right,
      exclusions: [ApplicationExclusionRule(bundleIdentifier: safari, triggerButton: .middle)])
    XCTAssertEqual(entries.map(\.id), [conditional.id])
    XCTAssertTrue(entries[0].requiresConditions)
    XCTAssertNil(entries[0].overriddenBy)
  }

  func testAdditionalSamplePreservesOriginalTemplates() throws {
    let original = try mapping("Original")
    let templates = try GestureAssistance.addingSample(
      stroke(0.1), to: original, mappings: [original], defaultTrigger: .right)
    XCTAssertEqual(templates.count, 2)
    XCTAssertEqual(templates.first, original.templates.first)
    XCTAssertNotEqual(templates.last, original.templates.first)
  }

  func testAdditionalSampleRejectsConflictAndSampleLimit() throws {
    let original = try mapping("Original")
    let other = try mapping("Conflicting", angle: 0.2)
    XCTAssertThrowsError(
      try GestureAssistance.addingSample(
        stroke(0.2), to: original,
        mappings: [original, other], defaultTrigger: .right)
    ) {
      XCTAssertEqual($0 as? GestureAssistance.SampleError, .conflict("Conflicting"))
    }
    var full = original
    full.templates = Array(repeating: original.templates[0], count: 5)
    XCTAssertThrowsError(
      try GestureAssistance.addingSample(
        stroke(), to: full, mappings: [full], defaultTrigger: .right)
    ) {
      XCTAssertEqual($0 as? GestureAssistance.SampleError, .full)
    }
    XCTAssertThrowsError(
      try GestureAssistance.addingSample(
        stroke(.pi), to: original, mappings: [original], defaultTrigger: .right)
    ) {
      XCTAssertEqual($0 as? GestureAssistance.SampleError, .tooDifferent)
    }
  }

  func testLegacyDiagnosticDecodesAndNewDetailsContainNoStroke() throws {
    let id = UUID()
    let old = Data("{\"id\":\"\(id)\",\"timestamp\":0,\"outcome\":\"noMatch\"}".utf8)
    XCTAssertNil(try JSONDecoder().decode(GestureDiagnosticRecord.self, from: old).detail)
    let report = diagnose([try mapping("Original")])
    let record = GestureDiagnosticRecord(outcome: report.outcome, detail: report)
    let data = try JSONEncoder().encode(record)
    XCTAssertEqual(try JSONDecoder().decode(GestureDiagnosticRecord.self, from: data), record)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let detail = try XCTUnwrap(json["detail"] as? [String: Any])
    XCTAssertEqual(Set(detail.keys), ["reason", "suggestions", "applicationBundleID"])
  }

  func testFailureMetadataFlowsThroughDiagnosticsBuffer() {
    let buffer = GestureDiagnosticsBuffer()
    let detail = GestureDiagnosticDetail(
      reason: .actionFailed,
      suggestions: [GestureSuggestion(mappingID: UUID(), name: "Script")], actionFailure: .timedOut)
    buffer.show(.diagnostic(detail))
    // Installing a handler emits the existing history, including its repair target.
    let received = expectation(description: "diagnostic history")
    buffer.setHandler { records in
      XCTAssertEqual(records.last?.detail, detail)
      XCTAssertEqual(records.last?.outcome, .actionFailed)
      received.fulfill()
    }
    wait(for: [received], timeout: 1)
  }

  func testPreviewHidesAmbiguousAndUnassignedSecondaryActions() throws {
    let first = try mapping("First", angle: 0.07)
    let second = try mapping("Second", angle: 0.12)
    let ambiguous = GesturePreviewContext(mappings: [first, second], bundleID: safari)
    XCTAssertNil(ambiguous.match(stroke(0.08)))
    var preview = GesturePreviewContext(mappings: [first], bundleID: safari)
    XCTAssertEqual(preview.match(stroke())?.mappingID, first.id)
    preview.useSecondaryAction = true
    XCTAssertNil(preview.match(stroke()))
    var withSecondary = first
    withSecondary.secondaryAction = action
    preview = GesturePreviewContext(
      mappings: [withSecondary], bundleID: safari, useSecondaryAction: true)
    XCTAssertEqual(preview.match(stroke())?.mappingID, first.id)
  }

  func testPreviewContextChangesWithoutMotionAndClearsOnHide() throws {
    var context = GesturePreviewContext(mappings: [try mapping("Original")], bundleID: safari)
    let buffer = OverlayEventBuffer()
    buffer.preparePreview(context)
    buffer.show(at: stroke()[0])
    XCTAssertEqual(buffer.drain()?.previewContext, context)
    context.useSecondaryAction = true
    buffer.preparePreview(context)
    XCTAssertEqual(buffer.drain()?.previewContext, context)
    XCTAssertNil(buffer.drain())
    buffer.hide()
    let hidden = try XCTUnwrap(buffer.drain())
    XCTAssertTrue(hidden.shouldHide)
    XCTAssertNil(hidden.previewContext)
    buffer.show(at: stroke()[0])
    XCTAssertNil(buffer.drain()?.previewContext)
  }

  func testPreviewReceivesTheStrokeBeforeActivation() {
    var session = GestureSession(configuration: .init(minimumTriggerDuration: 1))
    let origin = GesturePoint(x: 0, y: 0)
    let corner = GesturePoint(x: 0, y: 12)
    let endpoint = GesturePoint(x: 20, y: 12)
    _ = session.mouseDown(at: origin, timestamp: 0, frontmostBundleID: safari, shouldTrack: true)
    _ = session.mouseDragged(to: corner, timestamp: 0.01)
    let result = session.mouseDragged(to: endpoint, timestamp: 0.02)
    XCTAssertEqual(
      result.commands,
      [.showOverlay(at: origin), .appendOverlayPoint(corner), .appendOverlayPoint(endpoint)])
  }

  func testReferenceFiltersDisabledTrackpadAndExplainsDirectPriority() throws {
    var direct = try mapping("Double Click")
    direct.templates = []
    direct.inputVariant = .doubleClick(maximumInterval: 0.3)
    let preferred = GestureMapping(
      name: "Preferred", templates: [], action: action,
      inputVariant: direct.inputVariant, priority: -1)
    var trackpad = try mapping("Trackpad")
    trackpad.triggerButton = .trackpad
    let entries = GestureAssistance.reference(
      snapshot: CompiledMappingSnapshot(mappings: [direct, preferred, trackpad]),
      bundleID: safari, defaultTrigger: .right, trackpadGestureEnabled: false)
    XCTAssertFalse(entries.contains { $0.id == trackpad.id })
    XCTAssertEqual(entries.first { $0.id == direct.id }?.overriddenBy?.mappingID, preferred.id)
  }
}
