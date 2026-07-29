import Foundation
import XCTest

@testable import iGestures

final class MappingStoreTests: XCTestCase {
  private var directoryURL: URL!

  override func setUpWithError() throws {
    directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directoryURL)
    directoryURL = nil
  }

  func testSchemaRoundTripUsesStableAppScopeShape() async throws {
    let database = try makeDatabase(name: "First")
    let store = MappingStore(directoryURL: directoryURL)

    try await store.save(database)
    let reloaded = try await MappingStore(
      directoryURL: directoryURL
    ).load()
    let exported = try await store.exportData()
    let json = try XCTUnwrap(
      String(data: exported, encoding: .utf8)
    )

    XCTAssertEqual(reloaded, database)
    XCTAssertTrue(json.contains(#""type" : "only""#))
    XCTAssertTrue(json.contains(#""type" : "keyboardShortcut""#))
    XCTAssertTrue(json.contains(#""schemaVersion" : 2"#))
    XCTAssertFalse(json.contains(#""_0""#))
  }

  func testSchemaV1ShortcutMigratesWithoutChangingMapping()
    async throws
  {
    let database = try makeDatabase(name: "Legacy")
    let mappingData = try JSONEncoder().encode(
      database.mappings[0]
    )
    var mappingObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: mappingData)
        as? [String: Any]
    )
    mappingObject["shortcut"] = [
      "keyCode": 12,
      "modifiers": 0x10_0000,
    ]
    mappingObject.removeValue(forKey: "action")
    let legacyData = try JSONSerialization.data(
      withJSONObject: [
        "schemaVersion": 1,
        "mappings": [mappingObject],
      ]
    )

    let migrated = try await MappingStore(
      directoryURL: directoryURL
    ).replaceWithImportedData(legacyData)

    XCTAssertEqual(
      migrated.schemaVersion,
      GestureDatabase.currentSchemaVersion
    )
    XCTAssertEqual(migrated.mappings.count, 1)
    XCTAssertEqual(
      migrated.mappings[0].action,
      .keyboardShortcut(
        KeyboardShortcut(keyCode: 12, modifiers: 0x10_0000)
      )
    )
    XCTAssertEqual(
      migrated.mappings[0].templates,
      database.mappings[0].templates
    )
    XCTAssertEqual(
      migrated.mappings[0].appScope,
      database.mappings[0].appScope
    )
    XCTAssertEqual(
      migrated.mappings[0].priority,
      database.mappings[0].priority
    )
  }

  func testNonShortcutActionsRoundTrip() async throws {
    var database = try makeDatabase(name: "URL")
    database.mappings[0].action = .openURL(
      "https://example.com/path"
    )
    let store = MappingStore(directoryURL: directoryURL)

    try await store.save(database)
    let reloaded = try await store.load()

    XCTAssertEqual(reloaded, database)
  }

  func testCompoundBindingsRoundTripAndPreferApplicationScope()
    async throws
  {
    var database = try makeDatabase(name: "Base")
    let input = CompoundGestureInput.rocker(
      first: .right,
      second: .left
    )
    database.compoundBindings = [
      CompoundGestureBinding(
        name: "Global desktop",
        isEnabled: true,
        input: input,
        action: .system(.showDesktop)
      ),
      CompoundGestureBinding(
        name: "Finder mission control",
        isEnabled: true,
        input: input,
        action: .system(.missionControl),
        appScope: .only(["com.apple.finder"]),
        priority: 1
      ),
    ]
    let store = MappingStore(directoryURL: directoryURL)

    try await store.save(database)
    let reloaded = try await store.load()
    let exported = try await store.exportData()
    let json = try XCTUnwrap(
      String(data: exported, encoding: .utf8)
    )

    XCTAssertEqual(reloaded, database)
    XCTAssertEqual(
      reloaded.compiledSnapshot.compoundAction(
        for: input,
        bundleID: "com.apple.finder"
      )?.action,
      .system(.missionControl)
    )
    XCTAssertEqual(
      reloaded.compiledSnapshot.compoundAction(
        for: input,
        bundleID: "com.apple.Safari"
      )?.action,
      .system(.showDesktop)
    )
    XCTAssertNil(
      reloaded.compiledSnapshot.compoundAction(
        for: .wheel(trigger: .right, direction: .up),
        bundleID: "com.apple.finder"
      )
    )
    XCTAssertTrue(json.contains(#""type" : "rocker""#))
    XCTAssertFalse(json.contains(#""_0""#))
  }

  func testUnknownSchemaDoesNotOverwriteCurrentDatabase() async throws {
    let database = try makeDatabase(name: "Current")
    let store = MappingStore(directoryURL: directoryURL)
    try await store.save(database)

    let unsupported = GestureDatabase(
      schemaVersion: 99,
      mappings: database.mappings
    )
    let data = try JSONEncoder().encode(unsupported)

    do {
      _ = try await store.replaceWithImportedData(data)
      XCTFail("Expected an unsupported schema error")
    } catch {
      XCTAssertEqual(
        error as? MappingStoreError,
        .unsupportedSchema(found: 99)
      )
    }
    let reloaded = try await store.load()
    XCTAssertEqual(reloaded, database)
  }

  func testCorruptPrimaryRecoversLastSuccessfulBackup() async throws {
    let first = try makeDatabase(name: "First")
    let second = try makeDatabase(name: "Second")
    let store = MappingStore(directoryURL: directoryURL)
    try await store.save(first)
    try await store.save(second)

    try Data("corrupt".utf8).write(to: store.fileURL)

    let recovered = try await MappingStore(
      directoryURL: directoryURL
    ).load()
    let verified = try await MappingStore(
      directoryURL: directoryURL
    ).load()

    XCTAssertEqual(recovered, first)
    XCTAssertEqual(verified, first)
  }

  func testInvalidTemplatePointCountIsRejected() async throws {
    let template = GestureTemplate(
      points: [
        GesturePoint(x: 0, y: 0),
        GesturePoint(x: 1, y: 1),
      ],
      aspectRatio: 0,
      startDirection: GesturePoint(x: 1, y: 0),
      endDirection: GesturePoint(x: 1, y: 0)
    )
    let database = GestureDatabase(
      mappings: [
        GestureMapping(
          name: "Invalid",
          templates: [template],
          shortcut: KeyboardShortcut(keyCode: 1, modifiers: 0)
        )
      ]
    )

    do {
      try await MappingStore(directoryURL: directoryURL).save(database)
      XCTFail("Expected a point count error")
    } catch {
      XCTAssertEqual(
        error as? MappingStoreError,
        .invalidTemplatePointCount(required: 64)
      )
    }
  }

  func testClearedShortcutPersistsOnlyForDisabledMapping() async throws {
    var disabled = try makeDatabase(name: "Disabled")
    disabled.mappings[0].isEnabled = false
    disabled.mappings[0].shortcut =
      ShortcutRecordingSession.emptyShortcut
    let store = MappingStore(directoryURL: directoryURL)

    try await store.save(disabled)
    let reloaded = try await store.load()
    XCTAssertEqual(reloaded, disabled)

    var invalid = disabled
    invalid.mappings[0].isEnabled = true
    do {
      try await store.save(invalid)
      XCTFail("Expected an invalid shortcut error")
    } catch {
      XCTAssertEqual(
        error as? MappingStoreError,
        .invalidAction
      )
    }
  }

  func testConcurrentSavesNeverExposePartialJSON() async throws {
    let store = MappingStore(directoryURL: directoryURL)
    let databases = try (0..<20).map {
      try makeDatabase(name: "Mapping \($0)")
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for database in databases {
        group.addTask {
          try await store.save(database)
        }
      }
      try await group.waitForAll()
    }

    let loaded = try await MappingStore(
      directoryURL: directoryURL
    ).load()
    XCTAssertTrue(databases.contains(loaded))
  }

  func testFileImportAndExportUseValidatedDatabase() async throws {
    let original = try makeDatabase(name: "Exported")
    let exportURL = directoryURL.appendingPathComponent("export.json")
    let importDirectoryURL = directoryURL.appendingPathComponent(
      "imported",
      isDirectory: true
    )
    let sourceStore = MappingStore(directoryURL: directoryURL)
    try await sourceStore.save(original)

    try await sourceStore.exportData(to: exportURL)
    let imported = try await MappingStore(
      directoryURL: importDirectoryURL
    ).importData(from: exportURL)

    XCTAssertEqual(imported, original)
  }

  func testMergeImportDisablesScriptsAndCanBeUndone()
    async throws
  {
    let current = try makeDatabase(name: "Current")
    var imported = try makeDatabase(name: "Imported")
    imported.mappings[0].action = .script(
      AutomationScript(
        kind: .shell,
        source: "open https://example.com",
        isConfirmed: true
      )
    )
    let importURL = directoryURL.appendingPathComponent(
      "script-import.json"
    )
    try JSONEncoder().encode(imported).write(to: importURL)
    let store = MappingStore(directoryURL: directoryURL)
    try await store.save(current)

    let preview = try await store.previewImport(
      from: importURL,
      mode: .merge
    )
    let merged = try await store.importData(
      from: importURL,
      mode: .merge
    )

    XCTAssertEqual(preview.mappingsToAdd, 1)
    XCTAssertEqual(preview.scriptsRequiringConfirmation.count, 1)
    XCTAssertEqual(merged.mappings.count, 2)
    let importedMapping = try XCTUnwrap(
      merged.mappings.first { $0.name == "Imported" }
    )
    XCTAssertFalse(importedMapping.isEnabled)
    XCTAssertEqual(
      importedMapping.action.scripts.map(\.isConfirmed),
      [false]
    )
    let canUndo = await store.canUndoLastImport()
    XCTAssertTrue(canUndo)

    let restored = try await store.undoLastImport()
    XCTAssertEqual(restored, current)
    let canUndoAfterRestore = await store.canUndoLastImport()
    XCTAssertFalse(canUndoAfterRestore)
  }

  func testReplaceImportPreviewMatchesWrittenDatabase()
    async throws
  {
    let current = try makeDatabase(name: "Current")
    let imported = try makeDatabase(name: "Replacement")
    let importURL = directoryURL.appendingPathComponent(
      "replace-import.json"
    )
    try JSONEncoder().encode(imported).write(to: importURL)
    let store = MappingStore(directoryURL: directoryURL)
    try await store.save(current)

    let preview = try await store.previewImport(
      from: importURL,
      mode: .replace
    )
    let result = try await store.importData(
      from: importURL,
      mode: .replace
    )

    XCTAssertEqual(preview.mappingsToAdd, imported.mappings.count)
    XCTAssertEqual(preview.mappingsToReplace, current.mappings.count)
    XCTAssertEqual(result, imported)
  }

  func testOversizedImportDoesNotReplaceCurrentDatabase() async throws {
    let current = try makeDatabase(name: "Current")
    let store = MappingStore(directoryURL: directoryURL)
    try await store.save(current)
    let oversized = Data(
      repeating: 0x20,
      count: store.limits.maximumFileSize + 1
    )

    do {
      _ = try await store.replaceWithImportedData(oversized)
      XCTFail("Expected a file size error")
    } catch {
      XCTAssertEqual(
        error as? MappingStoreError,
        .fileTooLarge(limit: store.limits.maximumFileSize)
      )
    }
    let reloaded = try await store.load()
    XCTAssertEqual(reloaded, current)
  }

  func testOversizedFileImportDoesNotReplaceCurrentDatabase() async throws {
    let current = try makeDatabase(name: "Current")
    let limits = MappingStoreLimits(maximumFileSize: 100_000)
    let store = MappingStore(
      directoryURL: directoryURL,
      limits: limits
    )
    try await store.save(current)
    let importURL = directoryURL.appendingPathComponent("oversized.json")
    try Data(
      repeating: 0x20,
      count: limits.maximumFileSize + 1
    ).write(to: importURL)

    do {
      _ = try await store.importData(from: importURL)
      XCTFail("Expected a file size error")
    } catch {
      XCTAssertEqual(
        error as? MappingStoreError,
        .fileTooLarge(limit: limits.maximumFileSize)
      )
    }
    let persisted = await store.currentDatabase()
    XCTAssertEqual(persisted, current)
  }

  func testNoncanonicalShortcutModifiersAreRejected() async throws {
    var database = try makeDatabase(name: "Invalid Flags")
    database.mappings[0].shortcut = KeyboardShortcut(
      keyCode: 12,
      modifiers: 1
    )

    do {
      try await MappingStore(directoryURL: directoryURL).save(database)
      XCTFail("Expected an invalid shortcut error")
    } catch {
      XCTAssertEqual(
        error as? MappingStoreError,
        .invalidAction
      )
    }
  }

  func testImportedPrioritiesMustMatchArrayOrder() async throws {
    var database = try makeDatabase(name: "Invalid Priority")
    database.mappings[0].priority = 4

    do {
      try await MappingStore(directoryURL: directoryURL).save(database)
      XCTFail("Expected an invalid priority error")
    } catch {
      XCTAssertEqual(
        error as? MappingStoreError,
        .invalidPriority
      )
    }
  }

  func testValidationRejectsInvalidEditBeforeStoreMutation() async throws {
    let current = try makeDatabase(name: "Current")
    var invalid = current
    invalid.mappings[0].name = String(repeating: "x", count: 201)
    let store = MappingStore(directoryURL: directoryURL)
    try await store.save(current)

    XCTAssertThrowsError(try store.validate(invalid)) { error in
      XCTAssertEqual(
        error as? MappingStoreError,
        .invalidMappingName
      )
    }
    let persisted = await store.currentDatabase()
    XCTAssertEqual(persisted, current)
  }

  private func makeDatabase(name: String) throws -> GestureDatabase {
    let points = (0..<80).map {
      GesturePoint(x: Float($0) * 2, y: 0)
    }
    let template = try GestureNormalizer().normalize(points)
    return GestureDatabase(
      mappings: [
        GestureMapping(
          name: name,
          templates: [template],
          shortcut: KeyboardShortcut(
            keyCode: 12,
            modifiers: 0x10_0000
          ),
          appScope: .only(["com.apple.finder"])
        )
      ]
    )
  }
}
