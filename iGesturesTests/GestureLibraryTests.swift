import XCTest

@testable import iGestures

final class GestureLibraryTests: XCTestCase {
  func testCreateUpdateMoveAndDeleteKeepPrioritiesDense() throws {
    let template = try makeTemplate(angle: 0)
    var library = GestureLibrary()
    let firstID = library.create(
      draft(name: "First", template: template)
    )
    let secondID = library.create(
      draft(name: "Second", template: template)
    )
    let thirdID = library.create(
      draft(name: "Third", template: template)
    )

    try library.rename(id: firstID, to: "Renamed")
    try library.setEnabled(id: secondID, false)
    try library.setShortcut(
      id: thirdID,
      KeyboardShortcut(keyCode: 13, modifiers: 1)
    )
    try library.setAppScope(
      id: thirdID,
      .only(["com.apple.finder"])
    )
    try library.move(from: 2, to: 0)
    try library.delete(id: secondID)

    XCTAssertEqual(
      library.database.mappings.map(\.id),
      [thirdID, firstID]
    )
    XCTAssertEqual(
      library.database.mappings.map(\.priority),
      [0, 1]
    )
    XCTAssertEqual(
      library.database.mappings[1].name,
      "Renamed"
    )
    XCTAssertEqual(
      library.database.mappings[0].shortcut.keyCode,
      13
    )
  }

  func testMissingMappingAndInvalidMoveAreRejected() throws {
    let template = try makeTemplate(angle: 0)
    var library = GestureLibrary()
    _ = library.create(draft(name: "Only", template: template))

    XCTAssertThrowsError(
      try library.rename(id: UUID(), to: "Missing")
    )
    XCTAssertThrowsError(
      try library.move(from: 0, to: 2)
    )
  }

  func testBulkTargetMoveAndDeleteAreAtomic() throws {
    let template = try makeTemplate(angle: 0)
    var library = GestureLibrary()
    let firstID = library.create(
      draft(name: "First", template: template)
    )
    let secondID = library.create(
      draft(name: "Second", template: template)
    )
    let untouchedID = library.create(
      draft(name: "Untouched", template: template)
    )
    let groupID = UUID()

    try library.setTarget(
      ids: [firstID, secondID],
      appScope: .only(["com.apple.Safari"]),
      applicationGroupID: groupID
    )

    XCTAssertEqual(
      library.database.mappings.prefix(2).map(\.appScope),
      [.only(["com.apple.Safari"]), .only(["com.apple.Safari"])]
    )
    XCTAssertEqual(
      library.database.mappings.prefix(2).map(\.applicationGroupID),
      [groupID, groupID]
    )
    XCTAssertNil(library.database.mappings[2].applicationGroupID)

    try library.delete(ids: [firstID, secondID])

    XCTAssertEqual(library.database.mappings.map(\.id), [untouchedID])
    XCTAssertEqual(library.database.mappings.map(\.priority), [0])
  }

  func testBulkMutationRejectsMissingMappingWithoutPartialChanges() throws {
    let template = try makeTemplate(angle: 0)
    var library = GestureLibrary()
    let existingID = library.create(
      draft(name: "Existing", template: template)
    )
    let original = library.database

    XCTAssertThrowsError(
      try library.setTarget(
        ids: [existingID, UUID()],
        appScope: .all,
        applicationGroupID: nil
      )
    )
    XCTAssertEqual(library.database, original)

    XCTAssertThrowsError(
      try library.delete(ids: [existingID, UUID()])
    )
    XCTAssertEqual(library.database, original)
  }

  func testClearingShortcutDisablesMappingUntilRebound() throws {
    let template = try makeTemplate(angle: 0)
    var library = GestureLibrary()
    let id = library.create(
      draft(name: "Clearable", template: template)
    )

    try library.setShortcut(
      id: id,
      ShortcutRecordingSession.emptyShortcut
    )

    XCTAssertFalse(library.database.mappings[0].isEnabled)
    XCTAssertThrowsError(
      try library.setEnabled(id: id, true)
    ) {
      XCTAssertEqual(
        $0 as? GestureLibraryError,
        .missingAction
      )
    }

    try library.setShortcut(
      id: id,
      KeyboardShortcut(keyCode: 13, modifiers: 0)
    )
    try library.setEnabled(id: id, true)
    XCTAssertTrue(library.database.mappings[0].isEnabled)
  }

  func testDraftUpdateReplacesRecordedConfiguration() throws {
    let original = try makeTemplate(angle: 0)
    let replacement = try makeTemplate(angle: .pi / 2)
    var library = GestureLibrary()
    let id = library.create(
      draft(name: "Original", template: original)
    )
    let shortcut = KeyboardShortcut(keyCode: 13, modifiers: 0)

    try library.update(
      id: id,
      with: GestureMappingDraft(
        name: "Updated",
        templates: [replacement],
        shortcut: shortcut,
        appScope: .only(["com.apple.finder"]),
        isEnabled: false
      )
    )

    let mapping = try XCTUnwrap(library.database.mappings.first)
    XCTAssertEqual(mapping.name, "Updated")
    XCTAssertEqual(mapping.templates, [replacement])
    XCTAssertEqual(mapping.shortcut, shortcut)
    XCTAssertEqual(
      mapping.appScope,
      .only(["com.apple.finder"])
    )
    XCTAssertFalse(mapping.isEnabled)
  }

  func testCustomTriggerButtonCanBeAssignedToMapping() throws {
    let template = try makeTemplate(angle: 0)
    var library = GestureLibrary()
    let id = library.create(
      draft(name: "Custom Trigger", template: template)
    )
    let customButton = GestureTriggerButton(buttonNumber: 7)

    try library.setTriggerButton(id: id, customButton)

    let mapping = try XCTUnwrap(library.database.mappings.first)
    XCTAssertEqual(mapping.triggerButton, customButton)
    XCTAssertEqual(
      library.database.compiledSnapshot.mappings(
        for: customButton,
        default: .right
      ).map(\.id),
      [id]
    )
    XCTAssertTrue(
      library.database.compiledSnapshot.mappings(
        for: .right,
        default: .right
      ).isEmpty
    )
  }

  private func draft(
    name: String,
    template: GestureTemplate
  ) -> GestureMappingDraft {
    GestureMappingDraft(
      name: name,
      templates: [template],
      shortcut: KeyboardShortcut(keyCode: 12, modifiers: 0)
    )
  }

  private func makeTemplate(angle: Float) throws -> GestureTemplate {
    try GestureNormalizer().normalize(
      (0..<80).map { index in
        let distance = Float(index) * 2
        return GesturePoint(
          x: cosf(angle) * distance,
          y: sinf(angle) * distance
        )
      }
    )
  }
}
