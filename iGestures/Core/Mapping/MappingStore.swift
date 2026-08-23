import Foundation

public struct MappingStoreLimits: Equatable, Sendable {
  public let maximumFileSize: Int
  public let maximumMappingCount: Int
  public let maximumTemplatesPerMapping: Int
  public let requiredPointsPerTemplate: Int
  public let maximumNameLength: Int
  public let maximumBundleIDsPerScope: Int
  public let maximumBundleIDLength: Int
  public let maximumConfigurationSetCount: Int
  public let maximumNamedActionCount: Int
  public let maximumChordButtonCount: Int
  public let maximumContextValueCount: Int

  public init(
    maximumFileSize: Int = 5 * 1_024 * 1_024,
    maximumMappingCount: Int = 500,
    maximumTemplatesPerMapping: Int = 5,
    requiredPointsPerTemplate: Int = 64,
    maximumNameLength: Int = 200,
    maximumBundleIDsPerScope: Int = 100,
    maximumBundleIDLength: Int = 255,
    maximumConfigurationSetCount: Int = 50,
    maximumNamedActionCount: Int = 100,
    maximumChordButtonCount: Int = 4,
    maximumContextValueCount: Int = 20
  ) {
    self.maximumFileSize = max(1, maximumFileSize)
    self.maximumMappingCount = max(1, maximumMappingCount)
    self.maximumTemplatesPerMapping = max(
      1,
      maximumTemplatesPerMapping
    )
    self.requiredPointsPerTemplate = max(
      2,
      requiredPointsPerTemplate
    )
    self.maximumNameLength = max(1, maximumNameLength)
    self.maximumBundleIDsPerScope = max(
      1,
      maximumBundleIDsPerScope
    )
    self.maximumBundleIDLength = max(1, maximumBundleIDLength)
    self.maximumConfigurationSetCount = max(
      1,
      maximumConfigurationSetCount
    )
    self.maximumNamedActionCount = max(1, maximumNamedActionCount)
    self.maximumChordButtonCount = max(1, maximumChordButtonCount)
    self.maximumContextValueCount = max(1, maximumContextValueCount)
  }
}

public enum MappingStoreError: Error, Equatable, Sendable {
  case fileTooLarge(limit: Int)
  case unsupportedSchema(found: Int)
  case tooManyMappings(limit: Int)
  case duplicateMappingID
  case invalidMappingName
  case invalidPriority
  case invalidAction
  case invalidTemplateCount(limit: Int)
  case invalidTemplatePointCount(required: Int)
  case nonFiniteTemplate
  case tooManyBundleIDs(limit: Int)
  case invalidBundleID
  case invalidApplicationGroup
  case invalidConfigurationSet
  case invalidNamedAction
  case cyclicNamedAction
  case invalidInputVariant
  case invalidContextCondition
  case invalidData
  case recoveryFailed
  case fileSystemFailure
}

public enum MappingImportMode: String, CaseIterable, Sendable {
  case merge
  case replace
}

public enum MappingImportConflict: Equatable, Sendable {
  case changedStableID(UUID)
  case similarGesture(existingID: UUID, importedID: UUID)
  case changedConfigurationSetID(UUID)
  case changedNamedActionID(UUID)
  case configurationSetName(String)
  case namedActionName(String)
}

public struct MappingImportPreview: Equatable, Sendable {
  public let schemaVersion: Int
  public let importedMappingCount: Int
  public let mappingsToAdd: Int
  public let mappingsToReplace: Int
  public let actionTypes: [String]
  public let conflicts: [MappingImportConflict]
  public let scriptsRequiringConfirmation: [AutomationScript]
  public let includesSettings: Bool
  public let importedConfigurationSetCount: Int
  public let importedNamedActionCount: Int
  public let packName: String?

  public init(
    schemaVersion: Int,
    importedMappingCount: Int,
    mappingsToAdd: Int,
    mappingsToReplace: Int,
    actionTypes: [String],
    conflicts: [MappingImportConflict],
    scriptsRequiringConfirmation: [AutomationScript],
    includesSettings: Bool = false,
    importedConfigurationSetCount: Int = 0,
    importedNamedActionCount: Int = 0,
    packName: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.importedMappingCount = importedMappingCount
    self.mappingsToAdd = mappingsToAdd
    self.mappingsToReplace = mappingsToReplace
    self.actionTypes = actionTypes
    self.conflicts = conflicts
    self.scriptsRequiringConfirmation = scriptsRequiringConfirmation
    self.includesSettings = includesSettings
    self.importedConfigurationSetCount = importedConfigurationSetCount
    self.importedNamedActionCount = importedNamedActionCount
    self.packName = packName
  }
}

public struct IGesturesGesturePack: Codable, Equatable, Sendable {
  public static let currentFormatVersion = 1

  public let formatVersion: Int
  public let name: String
  public let database: GestureDatabase

  public init(name: String, database: GestureDatabase) {
    self.formatVersion = Self.currentFormatVersion
    self.name = name
    self.database = database
  }
}

public struct IGesturesConfigurationArchive:
  Codable,
  Equatable,
  Sendable
{
  public static let currentFormatVersion = 1

  public let formatVersion: Int
  public let gestureDatabase: GestureDatabase
  public let settings: AppSettingsSnapshot

  public init(
    gestureDatabase: GestureDatabase,
    settings: AppSettingsSnapshot
  ) {
    self.formatVersion = Self.currentFormatVersion
    self.gestureDatabase = gestureDatabase
    self.settings = settings
  }
}

public struct ConfigurationImportResult: Equatable, Sendable {
  public let gestureDatabase: GestureDatabase
  public let settings: AppSettingsSnapshot?

  public init(
    gestureDatabase: GestureDatabase,
    settings: AppSettingsSnapshot?
  ) {
    self.gestureDatabase = gestureDatabase
    self.settings = settings
  }
}

private struct ConfigurationImportUndoArchive:
  Codable,
  Equatable,
  Sendable
{
  let gestureDatabase: GestureDatabase
  let settings: AppSettingsSnapshot?
}

private struct DecodedImportConfiguration {
  let gestureDatabase: GestureDatabase
  let settings: AppSettingsSnapshot?
  let packName: String?
}

public actor MappingStore {
  public static let defaultFileName = "gesture-mappings.json"
  public static let defaultBackupFileName =
    "gesture-mappings.backup.json"
  public static let defaultImportUndoFileName =
    "gesture-mappings.pre-import.json"

  public nonisolated let fileURL: URL
  public nonisolated let backupURL: URL
  public nonisolated let importUndoURL: URL
  public nonisolated let limits: MappingStoreLimits

  private let fileManager: FileManager
  private var database = GestureDatabase.empty

  public init(
    directoryURL: URL,
    limits: MappingStoreLimits = MappingStoreLimits(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = directoryURL.appendingPathComponent(
      Self.defaultFileName,
      isDirectory: false
    )
    self.backupURL = directoryURL.appendingPathComponent(
      Self.defaultBackupFileName,
      isDirectory: false
    )
    self.importUndoURL = directoryURL.appendingPathComponent(
      Self.defaultImportUndoFileName,
      isDirectory: false
    )
    self.limits = limits
    self.fileManager = fileManager
  }

  public static func live(
    bundleIdentifier: String,
    limits: MappingStoreLimits = MappingStoreLimits()
  ) throws -> MappingStore {
    guard !bundleIdentifier.isEmpty else {
      throw MappingStoreError.fileSystemFailure
    }
    let baseURL = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return MappingStore(
      directoryURL: baseURL.appendingPathComponent(
        bundleIdentifier,
        isDirectory: true
      ),
      limits: limits
    )
  }

  @discardableResult
  public func load() throws -> GestureDatabase {
    try ensureDirectoryExists()
    guard fileManager.fileExists(atPath: fileURL.path) else {
      database = .empty
      return database
    }

    do {
      database = try decodeAndValidate(
        readData(at: fileURL)
      )
      return database
    } catch {
      guard fileManager.fileExists(atPath: backupURL.path) else {
        throw normalize(error)
      }
      do {
        let backupData = try readData(at: backupURL)
        let recovered = try decodeAndValidate(backupData)
        try writePrimary(backupData, preserveCurrentAsBackup: false)
        database = recovered
        return recovered
      } catch {
        throw MappingStoreError.recoveryFailed
      }
    }
  }

  public func currentDatabase() -> GestureDatabase {
    database
  }

  public func currentSnapshot() -> CompiledMappingSnapshot {
    database.compiledSnapshot
  }

  public func save(_ newDatabase: GestureDatabase) throws {
    try validate(newDatabase)
    let data = try encode(newDatabase)
    try writePrimary(data, preserveCurrentAsBackup: true)
    database = newDatabase
  }

  @discardableResult
  public func replaceWithImportedData(
    _ data: Data
  ) throws -> GestureDatabase {
    let imported = try decodeAndValidate(data)
    try save(imported)
    return imported
  }

  public func exportData() throws -> Data {
    try validate(database)
    return try encode(database)
  }

  public func exportConfiguration(
    settings: AppSettingsSnapshot
  ) throws -> Data {
    try validate(database)
    return try encode(
      IGesturesConfigurationArchive(
        gestureDatabase: database,
        settings: settings
      )
    )
  }

  public func exportGesturePack(
    name: String,
    mappingIDs: Set<UUID>
  ) throws -> Data {
    let normalizedName = name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalizedName.isEmpty,
      normalizedName.utf8.count <= limits.maximumNameLength,
      !mappingIDs.isEmpty
    else {
      throw MappingStoreError.invalidData
    }
    let selectedMappings = database.mappings.filter {
      mappingIDs.contains($0.id)
    }
    guard selectedMappings.count == mappingIDs.count else {
      throw MappingStoreError.invalidData
    }
    let configurationSetIDs = Set(
      selectedMappings.compactMap(\.configurationSetID)
    )
    let namedActionIDs = referencedNamedActionClosure(
      for: selectedMappings,
      namedActions: database.namedActions
    )
    let applicationGroupIDs = Set(
      selectedMappings.compactMap(\.applicationGroupID)
    )
    let packDatabase = GestureDatabase(
      mappings: selectedMappings.enumerated().map { index, mapping in
        var normalized = mapping
        normalized.priority = index
        return normalized
      },
      applicationGroups: database.applicationGroups.filter {
        applicationGroupIDs.contains($0.id)
      },
      managedApplicationBundleIdentifiers:
        normalizedBundleIdentifiers(
          selectedMappings.flatMap { mapping -> [String] in
            switch mapping.appScope {
            case .all:
              return []
            case .only(let values), .allExcept(let values):
              return values
            }
          }
        ),
      configurationSets: database.configurationSets.filter {
        configurationSetIDs.contains($0.id)
      },
      namedActions: database.namedActions.filter {
        namedActionIDs.contains($0.id)
      }
    )
    try validate(packDatabase)
    return try encode(
      IGesturesGesturePack(
        name: normalizedName,
        database: packDatabase
      )
    )
  }

  public func importData(from sourceURL: URL) throws -> GestureDatabase {
    try importData(from: sourceURL, mode: .merge)
  }

  public func previewImport(
    from sourceURL: URL,
    mode: MappingImportMode = .merge
  ) throws -> MappingImportPreview {
    let imported = try decodeImportConfiguration(
      readData(at: sourceURL)
    )
    return makeImportPlan(
      imported.gestureDatabase,
      mode: mode,
      includesSettings: imported.settings != nil,
      packName: imported.packName
    ).preview
  }

  public func importData(
    from sourceURL: URL,
    mode: MappingImportMode
  ) throws -> GestureDatabase {
    let imported = try decodeImportConfiguration(
      readData(at: sourceURL)
    )
    let plan = makeImportPlan(
      imported.gestureDatabase,
      mode: mode,
      packName: imported.packName
    )
    try ensureDirectoryExists()
    try encode(database).write(to: importUndoURL, options: .atomic)
    do {
      try save(plan.database)
      return plan.database
    } catch {
      try? fileManager.removeItem(at: importUndoURL)
      throw error
    }
  }

  public func importConfiguration(
    from sourceURL: URL,
    mode: MappingImportMode,
    currentSettings: AppSettingsSnapshot
  ) throws -> ConfigurationImportResult {
    let imported = try decodeImportConfiguration(
      readData(at: sourceURL)
    )
    let plan = makeImportPlan(
      imported.gestureDatabase,
      mode: mode,
      includesSettings: imported.settings != nil,
      packName: imported.packName
    )
    let undoArchive = ConfigurationImportUndoArchive(
      gestureDatabase: database,
      settings: imported.settings == nil ? nil : currentSettings
    )
    try ensureDirectoryExists()
    try encode(undoArchive).write(
      to: importUndoURL,
      options: .atomic
    )
    do {
      try save(plan.database)
      return ConfigurationImportResult(
        gestureDatabase: plan.database,
        settings: imported.settings
      )
    } catch {
      try? fileManager.removeItem(at: importUndoURL)
      throw error
    }
  }

  public func canUndoLastImport() -> Bool {
    fileManager.fileExists(atPath: importUndoURL.path)
  }

  public func undoLastImport() throws -> GestureDatabase {
    try undoConfigurationImport().gestureDatabase
  }

  public func undoConfigurationImport() throws
    -> ConfigurationImportResult
  {
    guard fileManager.fileExists(atPath: importUndoURL.path) else {
      throw MappingStoreError.fileSystemFailure
    }
    let data = try readData(at: importUndoURL)
    let restored: ConfigurationImportResult
    if let archive = try? JSONDecoder().decode(
      ConfigurationImportUndoArchive.self,
      from: data
    ) {
      try validate(archive.gestureDatabase)
      restored = ConfigurationImportResult(
        gestureDatabase: archive.gestureDatabase,
        settings: archive.settings
      )
    } else {
      restored = ConfigurationImportResult(
        gestureDatabase: try decodeAndValidate(data),
        settings: nil
      )
    }
    try save(restored.gestureDatabase)
    do {
      try fileManager.removeItem(at: importUndoURL)
    } catch {
      throw MappingStoreError.fileSystemFailure
    }
    return restored
  }

  public func exportData(to destinationURL: URL) throws {
    let data = try exportData()
    do {
      try data.write(to: destinationURL, options: .atomic)
    } catch {
      throw MappingStoreError.fileSystemFailure
    }
  }

  public func exportConfiguration(
    settings: AppSettingsSnapshot,
    to destinationURL: URL
  ) throws {
    let data = try exportConfiguration(settings: settings)
    do {
      try data.write(to: destinationURL, options: .atomic)
    } catch {
      throw MappingStoreError.fileSystemFailure
    }
  }

  public func exportGesturePack(
    name: String,
    mappingIDs: Set<UUID>,
    to destinationURL: URL
  ) throws {
    let data = try exportGesturePack(
      name: name,
      mappingIDs: mappingIDs
    )
    do {
      try data.write(to: destinationURL, options: .atomic)
    } catch {
      throw MappingStoreError.fileSystemFailure
    }
  }

  private func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [
      .prettyPrinted,
      .sortedKeys,
      .withoutEscapingSlashes,
    ]
    do {
      let data = try encoder.encode(value)
      guard data.count <= limits.maximumFileSize else {
        throw MappingStoreError.fileTooLarge(
          limit: limits.maximumFileSize
        )
      }
      return data
    } catch let error as MappingStoreError {
      throw error
    } catch {
      throw MappingStoreError.invalidData
    }
  }

  private func decodeAndValidate(_ data: Data) throws -> GestureDatabase {
    guard data.count <= limits.maximumFileSize else {
      throw MappingStoreError.fileTooLarge(
        limit: limits.maximumFileSize
      )
    }
    let decoded: GestureDatabase
    do {
      decoded = try JSONDecoder().decode(
        GestureDatabase.self,
        from: data
      )
    } catch {
      throw MappingStoreError.invalidData
    }
    try validate(decoded)
    return decoded
  }

  private func decodeImportConfiguration(
    _ data: Data
  ) throws -> DecodedImportConfiguration {
    guard data.count <= limits.maximumFileSize else {
      throw MappingStoreError.fileTooLarge(
        limit: limits.maximumFileSize
      )
    }
    if let pack = try? JSONDecoder().decode(
      IGesturesGesturePack.self,
      from: data
    ) {
      guard
        pack.formatVersion == IGesturesGesturePack.currentFormatVersion,
        !pack.name.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
      else {
        throw MappingStoreError.invalidData
      }
      try validate(pack.database)
      return DecodedImportConfiguration(
        gestureDatabase: pack.database,
        settings: nil,
        packName: pack.name
      )
    }
    if let archive = try? JSONDecoder().decode(
      IGesturesConfigurationArchive.self,
      from: data
    ) {
      guard
        archive.formatVersion
          == IGesturesConfigurationArchive.currentFormatVersion
      else {
        throw MappingStoreError.invalidData
      }
      try validate(archive.gestureDatabase)
      return DecodedImportConfiguration(
        gestureDatabase: archive.gestureDatabase,
        settings: archive.settings,
        packName: nil
      )
    }
    return DecodedImportConfiguration(
      gestureDatabase: try decodeAndValidate(data),
      settings: nil,
      packName: nil
    )
  }

  private func makeImportPlan(
    _ imported: GestureDatabase,
    mode: MappingImportMode,
    includesSettings: Bool = false,
    packName: String? = nil
  ) -> (
    database: GestureDatabase,
    preview: MappingImportPreview
  ) {
    let existingByID = Dictionary(
      uniqueKeysWithValues: database.mappings.map { ($0.id, $0) }
    )
    var conflicts: [MappingImportConflict] = []
    var additions: [GestureMapping] = []
    let importedNamedActionsByID = Dictionary(
      uniqueKeysWithValues: imported.namedActions.map { ($0.id, $0) }
    )
    let discoveredScripts =
      imported.mappings.flatMap {
        scripts(
          in: $0.action,
          namedActionsByID: importedNamedActionsByID,
          resolving: []
        )
          + scripts(
            in: $0.secondaryAction ?? .none,
            namedActionsByID: importedNamedActionsByID,
            resolving: []
          )
      }
      + imported.namedActions.flatMap {
        scripts(
          in: $0.action,
          namedActionsByID: importedNamedActionsByID,
          resolving: []
        )
      }
    var seenScripts = Set<AutomationScript>()
    let importedScripts = discoveredScripts.filter {
      seenScripts.insert($0).inserted
    }
    let safeImportedMappings = imported.mappings.map { mapping in
      let containsScripts =
        !scripts(
          in: mapping.action,
          namedActionsByID: importedNamedActionsByID,
          resolving: []
        ).isEmpty
        || !scripts(
          in: mapping.secondaryAction ?? .none,
          namedActionsByID: importedNamedActionsByID,
          resolving: []
        ).isEmpty
      guard containsScripts else { return mapping }
      var safe = mapping
      safe.action = safe.action.disablingScripts()
      safe.secondaryAction =
        safe.secondaryAction?.disablingScripts()
      safe.isEnabled = false
      return safe
    }
    let safeImportedNamedActions = imported.namedActions.map { item in
      var safe = item
      let containsScripts = !scripts(
        in: item.action,
        namedActionsByID: importedNamedActionsByID,
        resolving: []
      ).isEmpty
      safe.action = safe.action.disablingScripts()
      safe.isEnabled = safe.isEnabled && !containsScripts
      safe.allowsAppIntent = safe.allowsAppIntent && !containsScripts
      return safe
    }

    for mapping in safeImportedMappings {
      if let existing = existingByID[mapping.id] {
        if existing != mapping {
          conflicts.append(.changedStableID(mapping.id))
        }
        continue
      }
      if let similar = similarMapping(to: mapping) {
        conflicts.append(
          .similarGesture(
            existingID: similar.id,
            importedID: mapping.id
          )
        )
      }
      additions.append(mapping)
    }

    let plannedMappings: [GestureMapping]
    let replacements: Int
    switch mode {
    case .merge:
      plannedMappings = database.mappings + additions
      replacements = 0
    case .replace:
      plannedMappings = safeImportedMappings
      replacements = database.mappings.count
    }
    var normalized = plannedMappings
    for index in normalized.indices {
      normalized[index].priority = index
    }
    let plannedGroups: [GestureApplicationGroup]
    let plannedApplications: [String]
    let plannedConfigurationSets: [GestureConfigurationSet]
    let plannedNamedActions: [NamedGestureAction]
    switch mode {
    case .merge:
      let existingGroupIDs = Set(database.applicationGroups.map(\.id))
      plannedGroups =
        database.applicationGroups
        + imported.applicationGroups.filter {
          !existingGroupIDs.contains($0.id)
        }
      plannedApplications = normalizedBundleIdentifiers(
        database.managedApplicationBundleIdentifiers
          + imported.managedApplicationBundleIdentifiers
          + plannedGroups.flatMap(\.bundleIdentifiers)
      )
      let existingConfigurationSetsByID = Dictionary(
        uniqueKeysWithValues: database.configurationSets.map {
          ($0.id, $0)
        }
      )
      for item in imported.configurationSets
      where existingConfigurationSetsByID[item.id] != nil
        && existingConfigurationSetsByID[item.id] != item
      {
        conflicts.append(.changedConfigurationSetID(item.id))
      }
      var configurationSetNames = Set(
        database.configurationSets.map {
          normalizedComparableName($0.name)
        }
      )
      var additionalConfigurationSets: [GestureConfigurationSet] = []
      for var item in imported.configurationSets
      where existingConfigurationSetsByID[item.id] == nil {
        if configurationSetNames.contains(
          normalizedComparableName(item.name)
        ) {
          conflicts.append(.configurationSetName(item.name))
          item.name = uniqueImportedName(
            item.name,
            existingNames: configurationSetNames
          )
        }
        configurationSetNames.insert(normalizedComparableName(item.name))
        additionalConfigurationSets.append(item)
      }
      plannedConfigurationSets =
        database.configurationSets + additionalConfigurationSets
      let existingNamedActionsByID = Dictionary(
        uniqueKeysWithValues: database.namedActions.map { ($0.id, $0) }
      )
      for item in safeImportedNamedActions
      where existingNamedActionsByID[item.id] != nil
        && existingNamedActionsByID[item.id] != item
      {
        conflicts.append(.changedNamedActionID(item.id))
      }
      var namedActionNames = Set(
        database.namedActions.map {
          normalizedComparableName($0.name)
        }
      )
      var additionalNamedActions: [NamedGestureAction] = []
      for var item in safeImportedNamedActions
      where existingNamedActionsByID[item.id] == nil {
        if namedActionNames.contains(
          normalizedComparableName(item.name)
        ) {
          conflicts.append(.namedActionName(item.name))
          item.name = uniqueImportedName(
            item.name,
            existingNames: namedActionNames
          )
        }
        namedActionNames.insert(normalizedComparableName(item.name))
        additionalNamedActions.append(item)
      }
      plannedNamedActions = database.namedActions + additionalNamedActions
    case .replace:
      plannedGroups = imported.applicationGroups
      plannedApplications = imported.managedApplicationBundleIdentifiers
      plannedConfigurationSets = imported.configurationSets
      plannedNamedActions = safeImportedNamedActions
    }
    synchronizeGroupScopes(
      in: &normalized,
      applicationGroups: plannedGroups
    )
    let plannedDatabase = GestureDatabase(
      mappings: normalized,
      applicationGroups: plannedGroups,
      managedApplicationBundleIdentifiers: plannedApplications,
      configurationSets: plannedConfigurationSets,
      namedActions: plannedNamedActions
    )
    let preview = MappingImportPreview(
      schemaVersion: imported.schemaVersion,
      importedMappingCount: imported.mappings.count,
      mappingsToAdd:
        mode == .merge
        ? additions.count
        : imported.mappings.count,
      mappingsToReplace: replacements,
      actionTypes: Array(
        Set(
          imported.mappings.flatMap { mapping in
            var types = [actionType(mapping.action)]
            if let secondaryAction = mapping.secondaryAction {
              types.append(actionType(secondaryAction))
            }
            return types
          }
        )
      ).sorted(),
      conflicts: conflicts,
      scriptsRequiringConfirmation: importedScripts,
      includesSettings: includesSettings,
      importedConfigurationSetCount: imported.configurationSets.count,
      importedNamedActionCount: imported.namedActions.count,
      packName: packName
    )
    return (plannedDatabase, preview)
  }

  private func similarMapping(
    to imported: GestureMapping
  ) -> GestureMapping? {
    let recognizer = GestureRecognizer()
    return database.mappings.first { existing in
      guard
        existing.appScope.competes(with: imported.appScope),
        existing.applicationGroupID == imported.applicationGroupID,
        existing.triggerButton == imported.triggerButton,
        existing.requiredChordButtons == imported.requiredChordButtons,
        existing.inputVariant == imported.inputVariant,
        existing.contextCondition == imported.contextCondition,
        existing.configurationSetID == imported.configurationSetID
      else {
        return false
      }
      return imported.templates.contains { importedTemplate in
        existing.templates.contains { existingTemplate in
          recognizer.distance(
            from: importedTemplate,
            to: existingTemplate
          ) < 0.12
        }
      }
    }
  }

  private func actionType(_ action: GestureAction) -> String {
    switch action {
    case .none:
      "none"
    case .keyboardShortcut:
      "keyboardShortcut"
    case .openURL:
      "openURL"
    case .openPath:
      "openPath"
    case .launchApplication:
      "launchApplication"
    case .system:
      "system"
    case .window:
      "window"
    case .customWindow:
      "customWindow"
    case .typeText:
      "typeText"
    case .applicationMenu:
      "applicationMenu"
    case .appleShortcut:
      "appleShortcut"
    case .namedAction:
      "namedAction"
    case .sequence:
      "sequence"
    case .script:
      "script"
    }
  }

  private func referencedNamedActionClosure(
    for mappings: [GestureMapping],
    namedActions: [NamedGestureAction]
  ) -> Set<UUID> {
    let namedActionsByID = Dictionary(
      uniqueKeysWithValues: namedActions.map { ($0.id, $0) }
    )
    var pending = Array(
      mappings.reduce(into: Set<UUID>()) { result, mapping in
        result.formUnion(referencedNamedActionIDs(in: mapping.action))
        if let secondaryAction = mapping.secondaryAction {
          result.formUnion(
            referencedNamedActionIDs(in: secondaryAction)
          )
        }
      }
    )
    var result = Set<UUID>()
    while let id = pending.popLast() {
      guard result.insert(id).inserted,
        let namedAction = namedActionsByID[id]
      else {
        continue
      }
      pending.append(
        contentsOf: referencedNamedActionIDs(in: namedAction.action)
      )
    }
    return result
  }

  private func scripts(
    in action: GestureAction,
    namedActionsByID: [UUID: NamedGestureAction],
    resolving: Set<UUID>
  ) -> [AutomationScript] {
    switch action {
    case .namedAction(let id):
      guard !resolving.contains(id),
        let namedAction = namedActionsByID[id]
      else {
        return []
      }
      var nextResolving = resolving
      nextResolving.insert(id)
      return scripts(
        in: namedAction.action,
        namedActionsByID: namedActionsByID,
        resolving: nextResolving
      )
    case .sequence(let sequence):
      let stepScripts = sequence.steps.flatMap {
        scripts(
          in: $0.action,
          namedActionsByID: namedActionsByID,
          resolving: resolving
        )
      }
      guard case .fallback(let fallback) = sequence.failurePolicy else {
        return stepScripts
      }
      return stepScripts
        + scripts(
          in: fallback,
          namedActionsByID: namedActionsByID,
          resolving: resolving
        )
    case .script(let script):
      return [script]
    default:
      return []
    }
  }

  private func readData(at url: URL) throws -> Data {
    do {
      let fileSize = try url.resourceValues(
        forKeys: [.fileSizeKey]
      ).fileSize
      if let fileSize, fileSize > limits.maximumFileSize {
        throw MappingStoreError.fileTooLarge(
          limit: limits.maximumFileSize
        )
      }

      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      guard data.count <= limits.maximumFileSize else {
        throw MappingStoreError.fileTooLarge(
          limit: limits.maximumFileSize
        )
      }
      return data
    } catch let error as MappingStoreError {
      throw error
    } catch {
      throw MappingStoreError.fileSystemFailure
    }
  }

  public nonisolated func validate(
    _ database: GestureDatabase
  ) throws {
    guard database.schemaVersion == GestureDatabase.currentSchemaVersion
    else {
      throw MappingStoreError.unsupportedSchema(
        found: database.schemaVersion
      )
    }
    guard database.mappings.count <= limits.maximumMappingCount else {
      throw MappingStoreError.tooManyMappings(
        limit: limits.maximumMappingCount
      )
    }
    guard
      Set(database.mappings.map(\.id)).count
        == database.mappings.count
    else {
      throw MappingStoreError.duplicateMappingID
    }

    guard
      database.configurationSets.count
        <= limits.maximumConfigurationSetCount,
      Set(database.configurationSets.map(\.id)).count
        == database.configurationSets.count,
      Set(
        database.configurationSets.map {
          $0.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
          )
        }
      ).count == database.configurationSets.count,
      database.configurationSets.allSatisfy({
        let name = $0.name.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        return !name.isEmpty
          && name.utf8.count <= limits.maximumNameLength
      })
    else {
      throw MappingStoreError.invalidConfigurationSet
    }

    guard
      database.namedActions.count <= limits.maximumNamedActionCount,
      Set(database.namedActions.map(\.id)).count
        == database.namedActions.count,
      Set(
        database.namedActions.map {
          $0.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
          )
        }
      ).count == database.namedActions.count,
      database.namedActions.allSatisfy({
        let name = $0.name.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        return !name.isEmpty
          && name.utf8.count <= limits.maximumNameLength
          && $0.action.performsAction
      })
    else {
      throw MappingStoreError.invalidNamedAction
    }
    let namedActionsByID = Dictionary(
      uniqueKeysWithValues: database.namedActions.map { ($0.id, $0) }
    )
    for namedAction in database.namedActions {
      try validate(
        namedAction.action,
        isEnabled: namedAction.isEnabled,
        namedActionsByID: namedActionsByID
      )
      try validateNamedActionGraph(
        namedAction.id,
        namedActionsByID: namedActionsByID,
        resolving: []
      )
    }
    let compiledNamedActions = database.compiledSnapshot.namedActions
    guard
      compiledNamedActions.allSatisfy({
        !$0.allowsAppIntent
          || ($0.isEnabled && $0.action.isSafeForAppIntent)
      })
    else {
      throw MappingStoreError.invalidNamedAction
    }
    let configurationSetIDs = Set(database.configurationSets.map(\.id))

    for (index, mapping) in database.mappings.enumerated() {
      guard
        !mapping.name.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty,
        mapping.name.utf8.count <= limits.maximumNameLength
      else {
        throw MappingStoreError.invalidMappingName
      }
      guard mapping.priority == index else {
        throw MappingStoreError.invalidPriority
      }
      if let category = mapping.category,
        category.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
          || category.utf8.count > limits.maximumNameLength
      {
        throw MappingStoreError.invalidMappingName
      }
      try validate(
        mapping.action,
        isEnabled: mapping.isEnabled,
        namedActionsByID: namedActionsByID
      )
      if let secondaryAction = mapping.secondaryAction {
        try validate(
          secondaryAction,
          isEnabled: mapping.isEnabled,
          namedActionsByID: namedActionsByID
        )
      }
      guard
        mapping.configurationSetID.map(
          configurationSetIDs.contains
        ) ?? true
      else {
        throw MappingStoreError.invalidConfigurationSet
      }
      let chordButtons = mapping.requiredChordButtons
      guard chordButtons.count <= limits.maximumChordButtonCount,
        Set(chordButtons).count == chordButtons.count,
        !chordButtons.contains(mapping.triggerButton ?? .right),
        chordButtons.allSatisfy({
          $0.keyboardKeyCode == nil && $0 != .trackpad
        }),
        mapping.inputVariant.isValid
      else {
        throw MappingStoreError.invalidInputVariant
      }
      let condition = mapping.contextCondition
      let normalizedRequired =
        ShortcutRecordingSession.normalizedModifiers(
          condition.requiredModifiers
        )
      let normalizedForbidden =
        ShortcutRecordingSession.normalizedModifiers(
          condition.forbiddenModifiers
        )
      guard condition.requiredModifiers == normalizedRequired,
        condition.forbiddenModifiers == normalizedForbidden,
        normalizedRequired & normalizedForbidden == 0,
        condition.displayIDs.count <= limits.maximumContextValueCount,
        Set(condition.displayIDs).count == condition.displayIDs.count,
        condition.connectedDeviceIdentifiers.count
          <= limits.maximumContextValueCount,
        Set(condition.connectedDeviceIdentifiers).count
          == condition.connectedDeviceIdentifiers.count,
        condition.connectedDeviceIdentifiers.allSatisfy({
          let value = $0.trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          return !value.isEmpty
            && value.utf8.count <= limits.maximumBundleIDLength
        })
      else {
        throw MappingStoreError.invalidContextCondition
      }
      guard !mapping.templates.isEmpty,
        mapping.templates.count <= limits.maximumTemplatesPerMapping
      else {
        throw MappingStoreError.invalidTemplateCount(
          limit: limits.maximumTemplatesPerMapping
        )
      }
      for template in mapping.templates {
        guard template.points.count == limits.requiredPointsPerTemplate
        else {
          throw MappingStoreError.invalidTemplatePointCount(
            required: limits.requiredPointsPerTemplate
          )
        }
        guard template.aspectRatio.isFinite,
          template.startDirection.isFinite,
          template.endDirection.isFinite,
          template.points.allSatisfy(\.isFinite)
        else {
          throw MappingStoreError.nonFiniteTemplate
        }
      }
      try validate(mapping.appScope)
    }

    guard
      Set(database.applicationGroups.map(\.id)).count
        == database.applicationGroups.count
    else {
      throw MappingStoreError.invalidApplicationGroup
    }
    var groupedBundleIdentifiers: Set<String> = []
    for group in database.applicationGroups {
      guard
        !group.name.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty,
        group.name.utf8.count <= limits.maximumNameLength,
        Set(group.bundleIdentifiers).count
          == group.bundleIdentifiers.count
      else {
        throw MappingStoreError.invalidApplicationGroup
      }
      try validateBundleIdentifiers(group.bundleIdentifiers)
      guard
        groupedBundleIdentifiers.isDisjoint(
          with: group.bundleIdentifiers
        )
      else {
        throw MappingStoreError.invalidApplicationGroup
      }
      groupedBundleIdentifiers.formUnion(group.bundleIdentifiers)
    }

    guard
      Set(database.managedApplicationBundleIdentifiers).count
        == database.managedApplicationBundleIdentifiers.count
    else {
      throw MappingStoreError.invalidBundleID
    }
    try validateBundleIdentifiers(
      database.managedApplicationBundleIdentifiers
    )

    let groupsByID = Dictionary(
      uniqueKeysWithValues: database.applicationGroups.map {
        ($0.id, $0)
      }
    )
    for mapping in database.mappings {
      guard let groupID = mapping.applicationGroupID else { continue }
      guard
        let group = groupsByID[groupID],
        case .only(let bundleIdentifiers) = mapping.appScope,
        bundleIdentifiers == group.bundleIdentifiers
      else {
        throw MappingStoreError.invalidApplicationGroup
      }
    }
  }

  private nonisolated func validate(
    _ action: GestureAction,
    isEnabled: Bool,
    namedActionsByID: [UUID: NamedGestureAction]
  ) throws {
    if case .keyboardShortcut(let shortcut) = action {
      let isCanonicalEmpty =
        shortcut == ShortcutRecordingSession.emptyShortcut
      let isCanonicalRecorded =
        shortcut.isValid
        && shortcut.modifiers
          == ShortcutRecordingSession.normalizedModifiers(
            shortcut.modifiers
          )
      guard
        isCanonicalRecorded || (!isEnabled && isCanonicalEmpty)
      else {
        throw MappingStoreError.invalidAction
      }
      return
    }
    for id in referencedNamedActionIDs(in: action) {
      guard namedActionsByID[id] != nil else {
        throw MappingStoreError.invalidNamedAction
      }
    }
    guard
      action.isValid
        || (!isEnabled
          && !action.scripts.isEmpty
          && action.isValid(allowingUnconfirmedScripts: true))
    else {
      throw MappingStoreError.invalidAction
    }
  }

  private nonisolated func referencedNamedActionIDs(
    in action: GestureAction
  ) -> Set<UUID> {
    switch action {
    case .namedAction(let id):
      return [id]
    case .sequence(let sequence):
      var result = Set(
        sequence.steps.flatMap {
          referencedNamedActionIDs(in: $0.action)
        }
      )
      if case .fallback(let fallback) = sequence.failurePolicy {
        result.formUnion(referencedNamedActionIDs(in: fallback))
      }
      return result
    default:
      return []
    }
  }

  private nonisolated func validateNamedActionGraph(
    _ id: UUID,
    namedActionsByID: [UUID: NamedGestureAction],
    resolving: Set<UUID>
  ) throws {
    guard !resolving.contains(id),
      let namedAction = namedActionsByID[id]
    else {
      throw MappingStoreError.cyclicNamedAction
    }
    var nextResolving = resolving
    nextResolving.insert(id)
    for referencedID in referencedNamedActionIDs(
      in: namedAction.action
    ) {
      guard namedActionsByID[referencedID] != nil else {
        throw MappingStoreError.invalidNamedAction
      }
      try validateNamedActionGraph(
        referencedID,
        namedActionsByID: namedActionsByID,
        resolving: nextResolving
      )
    }
  }

  private nonisolated func validate(_ scope: AppScope) throws {
    let bundleIDs: [String]
    switch scope {
    case .all:
      return
    case .only(let values), .allExcept(let values):
      bundleIDs = values
    }

    try validateBundleIdentifiers(bundleIDs)
  }

  private nonisolated func validateBundleIdentifiers(
    _ bundleIdentifiers: [String]
  ) throws {
    guard
      bundleIdentifiers.count <= limits.maximumBundleIDsPerScope
    else {
      throw MappingStoreError.tooManyBundleIDs(
        limit: limits.maximumBundleIDsPerScope
      )
    }
    guard
      bundleIdentifiers.allSatisfy({
        !$0.isEmpty && $0.utf8.count <= limits.maximumBundleIDLength
      })
    else {
      throw MappingStoreError.invalidBundleID
    }
  }

  private func synchronizeGroupScopes(
    in mappings: inout [GestureMapping],
    applicationGroups: [GestureApplicationGroup]
  ) {
    let groupsByID = Dictionary(
      uniqueKeysWithValues: applicationGroups.map { ($0.id, $0) }
    )
    for index in mappings.indices {
      guard
        let groupID = mappings[index].applicationGroupID,
        let group = groupsByID[groupID]
      else {
        continue
      }
      mappings[index].appScope = .only(group.bundleIdentifiers)
    }
  }

  private func normalizedBundleIdentifiers(
    _ bundleIdentifiers: [String]
  ) -> [String] {
    Array(
      Set(
        bundleIdentifiers.map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
      )
    ).sorted()
  }

  private func normalizedComparableName(_ name: String) -> String {
    name.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: .current
    )
  }

  private func uniqueImportedName(
    _ name: String,
    existingNames: Set<String>
  ) -> String {
    let base = String(name.prefix(max(1, limits.maximumNameLength - 24)))
    var candidate = "\(base) (Imported)"
    var suffix = 2
    while existingNames.contains(normalizedComparableName(candidate)) {
      candidate = "\(base) (Imported \(suffix))"
      suffix += 1
    }
    return candidate
  }

  private func writePrimary(
    _ data: Data,
    preserveCurrentAsBackup: Bool
  ) throws {
    try ensureDirectoryExists()
    let directoryURL = fileURL.deletingLastPathComponent()
    let pendingURL = directoryURL.appendingPathComponent(
      ".gesture-mappings.pending",
      isDirectory: false
    )
    let backupPendingURL = directoryURL.appendingPathComponent(
      ".gesture-mappings.backup.pending",
      isDirectory: false
    )
    defer {
      try? fileManager.removeItem(at: pendingURL)
      try? fileManager.removeItem(at: backupPendingURL)
    }

    do {
      try removeIfPresent(pendingURL)
      try data.write(to: pendingURL, options: .atomic)

      if preserveCurrentAsBackup,
        fileManager.fileExists(atPath: fileURL.path),
        let existingData = try? readData(at: fileURL),
        (try? decodeAndValidate(existingData)) != nil
      {
        try removeIfPresent(backupPendingURL)
        try existingData.write(to: backupPendingURL, options: .atomic)
        try replace(
          destination: backupURL,
          with: backupPendingURL
        )
      }

      try replace(destination: fileURL, with: pendingURL)
    } catch let error as MappingStoreError {
      throw error
    } catch {
      throw MappingStoreError.fileSystemFailure
    }
  }

  private func replace(destination: URL, with source: URL) throws {
    if fileManager.fileExists(atPath: destination.path) {
      _ = try fileManager.replaceItemAt(
        destination,
        withItemAt: source,
        backupItemName: nil,
        options: .usingNewMetadataOnly
      )
    } else {
      try fileManager.moveItem(at: source, to: destination)
    }
  }

  private func ensureDirectoryExists() throws {
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    } catch {
      throw MappingStoreError.fileSystemFailure
    }
  }

  private func removeIfPresent(_ url: URL) throws {
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  private func normalize(_ error: any Error) -> MappingStoreError {
    (error as? MappingStoreError) ?? .invalidData
  }
}
