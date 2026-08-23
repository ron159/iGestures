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
    XCTAssertTrue(json.contains(#""schemaVersion" : 5"#))
    XCTAssertFalse(json.contains(#""_0""#))
  }

  func testApplicationGroupsRoundTripWithManagedScope()
    async throws
  {
    let group = GestureApplicationGroup(
      name: "Browsers",
      bundleIdentifiers: [
        "com.apple.Safari",
        "com.microsoft.edgemac",
      ]
    )
    var database = try makeDatabase(name: "Group Back")
    database.applicationGroups = [group]
    database.managedApplicationBundleIdentifiers =
      group.bundleIdentifiers
    database.mappings[0].applicationGroupID = group.id
    database.mappings[0].appScope = .only(group.bundleIdentifiers)
    let store = MappingStore(directoryURL: directoryURL)

    try await store.save(database)
    let reloaded = try await store.load()

    XCTAssertEqual(reloaded, database)
    XCTAssertEqual(
      reloaded.applicationGroups.first?.bundleIdentifiers,
      group.bundleIdentifiers
    )
    XCTAssertEqual(
      reloaded.mappings.first?.applicationGroupID,
      group.id
    )
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

  func testSchemaV3MigratesWithoutSecondaryAction() async throws {
    let database = try makeDatabase(name: "Version 3")
    let encoded = try JSONEncoder().encode(database)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded)
        as? [String: Any]
    )
    object["schemaVersion"] = 3
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let migrated = try await MappingStore(
      directoryURL: directoryURL
    ).replaceWithImportedData(legacyData)

    XCTAssertEqual(
      migrated.schemaVersion,
      GestureDatabase.currentSchemaVersion
    )
    XCTAssertNil(migrated.mappings[0].secondaryAction)
    XCTAssertEqual(migrated.mappings[0].action, database.mappings[0].action)
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

  func testSecondaryWindowActionRoundTrips() async throws {
    var database = try makeDatabase(name: "Window")
    database.mappings[0].secondaryAction = .window(.topRightQuarter)
    let store = MappingStore(directoryURL: directoryURL)

    try await store.save(database)
    let reloaded = try await store.load()
    let exported = try await store.exportData()
    let json = try XCTUnwrap(
      String(data: exported, encoding: .utf8)
    )

    XCTAssertEqual(reloaded, database)
    XCTAssertEqual(
      reloaded.mappings[0].secondaryAction,
      .window(.topRightQuarter)
    )
    XCTAssertTrue(json.contains(#""secondaryAction""#))
    XCTAssertTrue(json.contains(#""type" : "window""#))
  }

  func testIndependentEmptyActionsRoundTrip() async throws {
    var database = try makeDatabase(name: "Independent")
    database.mappings[0].action = .none
    database.mappings[0].secondaryAction = .window(.maximize)
    let store = MappingStore(directoryURL: directoryURL)

    try await store.save(database)
    var reloaded = try await store.load()
    let exported = try await store.exportData()
    let json = try XCTUnwrap(
      String(data: exported, encoding: .utf8)
    )

    XCTAssertEqual(reloaded, database)
    XCTAssertEqual(reloaded.mappings[0].action, .none)
    XCTAssertEqual(
      reloaded.mappings[0].secondaryAction,
      .window(.maximize)
    )
    XCTAssertTrue(json.contains(#""type" : "none""#))

    reloaded.mappings[0].secondaryAction = nil
    try await store.save(reloaded)
    let bothEmptyReloaded = try await store.load()
    XCTAssertEqual(bothEmptyReloaded, reloaded)
  }

  func testRemovedCompoundBindingsAreIgnoredDuringLoad()
    async throws
  {
    let database = try makeDatabase(name: "Base")
    let encoded = try JSONEncoder().encode(database)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded)
        as? [String: Any]
    )
    let legacyBinding: [String: Any] = [
      "id": UUID().uuidString,
      "name": "Legacy Rocker",
      "isEnabled": true,
      "input": ["type": "rocker"],
    ]
    object["compoundBindings"] = [legacyBinding]
    let legacyData = try JSONSerialization.data(
      withJSONObject: object
    )
    let store = MappingStore(directoryURL: directoryURL)

    let migrated = try await store.replaceWithImportedData(legacyData)
    let exported = try await store.exportData()
    let json = try XCTUnwrap(
      String(data: exported, encoding: .utf8)
    )

    XCTAssertEqual(migrated, database)
    XCTAssertFalse(json.contains(#""compoundBindings""#))
    XCTAssertFalse(json.contains("Legacy Rocker"))
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

  func testLegacyGestureOnlyArchiveDoesNotReplaceAppSettings()
    async throws
  {
    let importedDatabase = try makeDatabase(name: "Legacy Export")
    let exportURL = directoryURL.appendingPathComponent(
      "legacy-gestures.json"
    )
    let sourceDirectoryURL = directoryURL.appendingPathComponent(
      "legacy-source",
      isDirectory: true
    )
    let destinationDirectoryURL = directoryURL.appendingPathComponent(
      "legacy-destination",
      isDirectory: true
    )
    let sourceStore = MappingStore(directoryURL: sourceDirectoryURL)
    let destinationStore = MappingStore(
      directoryURL: destinationDirectoryURL
    )
    try await sourceStore.save(importedDatabase)
    try await sourceStore.exportData(to: exportURL)

    let preview = try await destinationStore.previewImport(
      from: exportURL,
      mode: .replace
    )
    let imported = try await destinationStore.importConfiguration(
      from: exportURL,
      mode: .replace,
      currentSettings: AppSettingsSnapshot(
        interfaceAppearance: .dark
      )
    )

    XCTAssertFalse(preview.includesSettings)
    XCTAssertEqual(imported.gestureDatabase, importedDatabase)
    XCTAssertNil(imported.settings)
  }

  func testConfigurationArchiveImportsSettingsAndUndoRestoresBoth()
    async throws
  {
    let currentDatabase = try makeDatabase(name: "Current")
    let importedDatabase = try makeDatabase(name: "Imported")
    let currentSettings = AppSettingsSnapshot(
      interfaceAppearance: .system,
      interfaceLanguage: .system,
      recognitionSensitivity: .standard
    )
    let importedSettings = AppSettingsSnapshot(
      recognitionEnabled: false,
      overlayEnabled: false,
      interfaceAppearance: .dark,
      interfaceLanguage: .simplifiedChinese,
      recognitionSensitivity: .strict,
      feedbackEnabled: false,
      launchAtLoginEnabled: true
    )
    let sourceDirectoryURL = directoryURL.appendingPathComponent(
      "configuration-source",
      isDirectory: true
    )
    let exportURL = directoryURL.appendingPathComponent(
      "configuration.json"
    )
    let sourceStore = MappingStore(directoryURL: sourceDirectoryURL)
    let destinationStore = MappingStore(directoryURL: directoryURL)
    try await sourceStore.save(importedDatabase)
    try await sourceStore.exportConfiguration(
      settings: importedSettings,
      to: exportURL
    )
    try await destinationStore.save(currentDatabase)

    let preview = try await destinationStore.previewImport(
      from: exportURL,
      mode: .replace
    )
    let imported = try await destinationStore.importConfiguration(
      from: exportURL,
      mode: .replace,
      currentSettings: currentSettings
    )

    XCTAssertTrue(preview.includesSettings)
    XCTAssertEqual(imported.gestureDatabase, importedDatabase)
    XCTAssertEqual(imported.settings, importedSettings)

    let restored = try await destinationStore.undoConfigurationImport()
    let canUndoAfterRestore = await destinationStore.canUndoLastImport()

    XCTAssertEqual(restored.gestureDatabase, currentDatabase)
    XCTAssertEqual(restored.settings, currentSettings)
    XCTAssertFalse(canUndoAfterRestore)
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
    imported.mappings[0].secondaryAction = .script(
      AutomationScript(
        kind: .appleScript,
        source: "return true",
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
    XCTAssertEqual(preview.scriptsRequiringConfirmation.count, 2)
    XCTAssertEqual(merged.mappings.count, 2)
    let importedMapping = try XCTUnwrap(
      merged.mappings.first { $0.name == "Imported" }
    )
    XCTAssertFalse(importedMapping.isEnabled)
    XCTAssertEqual(
      importedMapping.action.scripts.map(\.isConfirmed),
      [false]
    )
    XCTAssertEqual(
      importedMapping.secondaryAction?.scripts.map(\.isConfirmed),
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

  func testGroupMappingScopeMustMatchManagedApplications() throws {
    let group = GestureApplicationGroup(
      name: "Browsers",
      bundleIdentifiers: ["com.apple.Safari"]
    )
    var database = try makeDatabase(name: "Invalid Group")
    database.applicationGroups = [group]
    database.mappings[0].applicationGroupID = group.id
    database.mappings[0].appScope = .only(["com.apple.finder"])

    XCTAssertThrowsError(
      try MappingStore(directoryURL: directoryURL).validate(database)
    ) { error in
      XCTAssertEqual(
        error as? MappingStoreError,
        .invalidApplicationGroup
      )
    }
  }

  func testNamedActionsExpandAndDisabledConfigurationSetsAreFiltered()
    throws
  {
    let enabledSet = GestureConfigurationSet(name: "Work")
    let disabledSet = GestureConfigurationSet(
      name: "Gaming",
      isEnabled: false
    )
    let leaf = NamedGestureAction(
      name: "Tile Left",
      action: .window(.leftHalf),
      allowsAppIntent: true
    )
    let wrapper = NamedGestureAction(
      name: "Reusable Layout",
      action: .sequence(
        GestureActionSequence(
          steps: [GestureActionStep(action: .namedAction(leaf.id))]
        )
      ),
      allowsAppIntent: true
    )
    var active = try makeDatabase(name: "Active").mappings[0]
    active.action = .namedAction(wrapper.id)
    active.configurationSetID = enabledSet.id
    var inactive = active
    inactive = GestureMapping(
      id: UUID(),
      name: "Inactive",
      templates: active.templates,
      action: .namedAction(leaf.id),
      configurationSetID: disabledSet.id,
      priority: 1
    )
    let database = GestureDatabase(
      mappings: [active, inactive],
      configurationSets: [enabledSet, disabledSet],
      namedActions: [leaf, wrapper]
    )

    try MappingStore(directoryURL: directoryURL).validate(database)
    let snapshot = database.compiledSnapshot

    XCTAssertEqual(snapshot.mappings.map(\.name), ["Active"])
    guard case .sequence(let sequence) = snapshot.mappings[0].action
    else {
      return XCTFail("Expected the named action to expand")
    }
    XCTAssertEqual(sequence.steps.map(\.action), [.window(.leftHalf)])
    XCTAssertTrue(
      snapshot.namedAction(named: "reusable layout")?
        .action.isSafeForAppIntent == true
    )
  }

  func testNamedActionCyclesAreRejected() throws {
    let firstID = UUID()
    let secondID = UUID()
    let database = GestureDatabase(
      mappings: [],
      namedActions: [
        NamedGestureAction(
          id: firstID,
          name: "First",
          action: .namedAction(secondID)
        ),
        NamedGestureAction(
          id: secondID,
          name: "Second",
          action: .namedAction(firstID)
        ),
      ]
    )

    XCTAssertThrowsError(
      try MappingStore(directoryURL: directoryURL).validate(database)
    ) { error in
      XCTAssertEqual(error as? MappingStoreError, .cyclicNamedAction)
    }
  }

  func testGesturePackIncludesOnlySelectedDependencies() async throws {
    let set = GestureConfigurationSet(name: "Shared Set")
    let leaf = NamedGestureAction(
      name: "Safe Window",
      action: .window(.maximize),
      allowsAppIntent: true
    )
    let wrapper = NamedGestureAction(
      name: "Shared Action",
      action: .namedAction(leaf.id),
      allowsAppIntent: true
    )
    var database = try makeDatabase(name: "Share Me")
    database.mappings[0].action = .namedAction(wrapper.id)
    database.mappings[0].configurationSetID = set.id
    database.configurationSets = [set]
    database.namedActions = [leaf, wrapper]
    let store = MappingStore(directoryURL: directoryURL)
    try await store.save(database)

    let data = try await store.exportGesturePack(
      name: "Window Pack",
      mappingIDs: [database.mappings[0].id]
    )
    let pack = try JSONDecoder().decode(
      IGesturesGesturePack.self,
      from: data
    )
    let packURL = directoryURL.appendingPathComponent(
      "Window Pack.igesturespack"
    )
    try data.write(to: packURL)
    let targetStore = MappingStore(
      directoryURL: directoryURL.appendingPathComponent("target")
    )
    let preview = try await targetStore.previewImport(from: packURL)

    XCTAssertEqual(pack.name, "Window Pack")
    XCTAssertEqual(pack.database.mappings.map(\.name), ["Share Me"])
    XCTAssertEqual(pack.database.configurationSets.map(\.name), ["Shared Set"])
    XCTAssertEqual(
      Set(pack.database.namedActions.map(\.name)),
      ["Safe Window", "Shared Action"]
    )
    XCTAssertEqual(preview.packName, "Window Pack")
    XCTAssertEqual(preview.importedConfigurationSetCount, 1)
    XCTAssertEqual(preview.importedNamedActionCount, 2)
  }

  func testImportedScriptNamedActionIsDisabledTransitively()
    async throws
  {
    let scriptAction = NamedGestureAction(
      name: "Imported Script",
      action: .script(
        AutomationScript(
          kind: .shell,
          source: "open https://example.com",
          isConfirmed: true
        )
      ),
      allowsAppIntent: false
    )
    var imported = try makeDatabase(name: "Script Reference")
    imported.mappings[0].action = .namedAction(scriptAction.id)
    imported.namedActions = [scriptAction]
    let importURL = directoryURL.appendingPathComponent("named-script.json")
    try JSONEncoder().encode(imported).write(to: importURL)
    let store = MappingStore(directoryURL: directoryURL)

    let preview = try await store.previewImport(from: importURL)
    let result = try await store.importData(
      from: importURL,
      mode: .replace
    )

    XCTAssertEqual(preview.scriptsRequiringConfirmation.count, 1)
    XCTAssertFalse(try XCTUnwrap(result.namedActions.first).isEnabled)
    XCTAssertEqual(
      result.namedActions.first?.action.scripts.map(\.isConfirmed),
      [false]
    )
    XCTAssertFalse(try XCTUnwrap(result.mappings.first).isEnabled)
  }

  func testDirectVariantsChordsAndBoundedContextMatchTogether()
    throws
  {
    var database = try makeDatabase(name: "Context Action")
    database.mappings[0].triggerButton = .button4
    database.mappings[0].requiredChordButtons = [.left]
    database.mappings[0].inputVariant = .longPress(
      minimumDuration: 0.6
    )
    database.mappings[0].contextCondition = GestureContextCondition(
      requiredModifiers: 0x10_0000,
      forbiddenModifiers: 0x8_0000,
      displayIDs: [42],
      connectedDeviceIdentifiers: ["123:456:7"]
    )
    try MappingStore(directoryURL: directoryURL).validate(database)
    let snapshot = database.compiledSnapshot
    let matching = GestureMatchContext(
      modifierFlags: 0x10_0000,
      displayID: 42,
      connectedDeviceIdentifiers: ["123:456:7"],
      heldButtons: [.left],
      inputVariant: .longPress(minimumDuration: 0.8)
    )

    XCTAssertNotNil(
      snapshot.directActionRequest(
        for: "com.apple.finder",
        triggerButton: .button4,
        default: .right,
        context: matching
      )
    )
    XCTAssertNil(
      snapshot.directActionRequest(
        for: "com.apple.finder",
        triggerButton: .button4,
        default: .right,
        context: GestureMatchContext(
          modifierFlags: 0x10_0000,
          displayID: 42,
          connectedDeviceIdentifiers: ["123:456:7"],
          heldButtons: [],
          inputVariant: .longPress(minimumDuration: 0.8)
        )
      )
    )
  }

  func testDoubleClickAndHeldScrollVariantsRespectTheirBounds()
    throws
  {
    let template = try makeDatabase(name: "Template").mappings[0]
      .templates
    let doubleClick = GestureMapping(
      name: "Double Click",
      templates: template,
      action: .window(.leftHalf),
      triggerButton: .button4,
      inputVariant: .doubleClick(maximumInterval: 0.5)
    )
    let scroll = GestureMapping(
      name: "Scroll Up",
      templates: template,
      action: .window(.rightHalf),
      triggerButton: .button5,
      inputVariant: .scrollWheel(direction: .up),
      priority: 1
    )
    let database = GestureDatabase(mappings: [doubleClick, scroll])
    try MappingStore(directoryURL: directoryURL).validate(database)
    let snapshot = database.compiledSnapshot

    XCTAssertNotNil(
      snapshot.directActionRequest(
        for: nil,
        triggerButton: .button4,
        default: .right,
        context: GestureMatchContext(
          inputVariant: .doubleClick(maximumInterval: 0.4)
        )
      )
    )
    XCTAssertNil(
      snapshot.directActionRequest(
        for: nil,
        triggerButton: .button4,
        default: .right,
        context: GestureMatchContext(
          inputVariant: .doubleClick(maximumInterval: 0.6)
        )
      )
    )
    XCTAssertNotNil(
      snapshot.directActionRequest(
        for: nil,
        triggerButton: .button5,
        default: .right,
        context: GestureMatchContext(
          inputVariant: .scrollWheel(direction: .up)
        )
      )
    )
    XCTAssertNil(
      snapshot.directActionRequest(
        for: nil,
        triggerButton: .button5,
        default: .right,
        context: GestureMatchContext(
          inputVariant: .scrollWheel(direction: .down)
        )
      )
    )
  }

  func testUnsafeNamedActionCannotBeExposedToAppIntents() throws {
    let database = GestureDatabase(
      mappings: [],
      namedActions: [
        NamedGestureAction(
          name: "Unsafe Typing",
          action: .typeText("secret"),
          allowsAppIntent: true
        )
      ]
    )

    XCTAssertThrowsError(
      try MappingStore(directoryURL: directoryURL).validate(database)
    ) { error in
      XCTAssertEqual(error as? MappingStoreError, .invalidNamedAction)
    }
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
