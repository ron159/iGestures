import Foundation

public struct MappingStoreLimits: Equatable, Sendable {
  public let maximumFileSize: Int
  public let maximumMappingCount: Int
  public let maximumTemplatesPerMapping: Int
  public let requiredPointsPerTemplate: Int
  public let maximumNameLength: Int
  public let maximumBundleIDsPerScope: Int
  public let maximumBundleIDLength: Int

  public init(
    maximumFileSize: Int = 5 * 1_024 * 1_024,
    maximumMappingCount: Int = 500,
    maximumTemplatesPerMapping: Int = 5,
    requiredPointsPerTemplate: Int = 64,
    maximumNameLength: Int = 200,
    maximumBundleIDsPerScope: Int = 100,
    maximumBundleIDLength: Int = 255
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
}

public struct MappingImportPreview: Equatable, Sendable {
  public let schemaVersion: Int
  public let importedMappingCount: Int
  public let mappingsToAdd: Int
  public let mappingsToReplace: Int
  public let actionTypes: [String]
  public let conflicts: [MappingImportConflict]
  public let scriptsRequiringConfirmation: [AutomationScript]

  public init(
    schemaVersion: Int,
    importedMappingCount: Int,
    mappingsToAdd: Int,
    mappingsToReplace: Int,
    actionTypes: [String],
    conflicts: [MappingImportConflict],
    scriptsRequiringConfirmation: [AutomationScript]
  ) {
    self.schemaVersion = schemaVersion
    self.importedMappingCount = importedMappingCount
    self.mappingsToAdd = mappingsToAdd
    self.mappingsToReplace = mappingsToReplace
    self.actionTypes = actionTypes
    self.conflicts = conflicts
    self.scriptsRequiringConfirmation = scriptsRequiringConfirmation
  }
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

  public func importData(from sourceURL: URL) throws -> GestureDatabase {
    try importData(from: sourceURL, mode: .merge)
  }

  public func previewImport(
    from sourceURL: URL,
    mode: MappingImportMode = .merge
  ) throws -> MappingImportPreview {
    let imported = try decodeAndValidate(readData(at: sourceURL))
    return makeImportPlan(imported, mode: mode).preview
  }

  public func importData(
    from sourceURL: URL,
    mode: MappingImportMode
  ) throws -> GestureDatabase {
    let imported = try decodeAndValidate(readData(at: sourceURL))
    let plan = makeImportPlan(imported, mode: mode)
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

  public func canUndoLastImport() -> Bool {
    fileManager.fileExists(atPath: importUndoURL.path)
  }

  public func undoLastImport() throws -> GestureDatabase {
    guard fileManager.fileExists(atPath: importUndoURL.path) else {
      throw MappingStoreError.fileSystemFailure
    }
    let restored = try decodeAndValidate(readData(at: importUndoURL))
    try save(restored)
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

  private func encode(_ database: GestureDatabase) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [
      .prettyPrinted,
      .sortedKeys,
      .withoutEscapingSlashes,
    ]
    do {
      let data = try encoder.encode(database)
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

  private func makeImportPlan(
    _ imported: GestureDatabase,
    mode: MappingImportMode
  ) -> (
    database: GestureDatabase,
    preview: MappingImportPreview
  ) {
    let existingByID = Dictionary(
      uniqueKeysWithValues: database.mappings.map { ($0.id, $0) }
    )
    var conflicts: [MappingImportConflict] = []
    var additions: [GestureMapping] = []
    let importedScripts = imported.mappings.flatMap {
      $0.action.scripts + ($0.secondaryAction?.scripts ?? [])
    }
    let safeImportedMappings = imported.mappings.map { mapping in
      let containsScripts =
        !mapping.action.scripts.isEmpty
        || !(mapping.secondaryAction?.scripts.isEmpty ?? true)
      guard containsScripts else { return mapping }
      var safe = mapping
      safe.action = safe.action.disablingScripts()
      safe.secondaryAction =
        safe.secondaryAction?.disablingScripts()
      safe.isEnabled = false
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
    case .replace:
      plannedGroups = imported.applicationGroups
      plannedApplications = imported.managedApplicationBundleIdentifiers
    }
    synchronizeGroupScopes(
      in: &normalized,
      applicationGroups: plannedGroups
    )
    let plannedDatabase = GestureDatabase(
      mappings: normalized,
      applicationGroups: plannedGroups,
      managedApplicationBundleIdentifiers: plannedApplications
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
      scriptsRequiringConfirmation: importedScripts
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
        existing.triggerButton == imported.triggerButton
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
    case .keyboardShortcut:
      "keyboardShortcut"
    case .openURL:
      "openURL"
    case .launchApplication:
      "launchApplication"
    case .system:
      "system"
    case .window:
      "window"
    case .appleShortcut:
      "appleShortcut"
    case .sequence:
      "sequence"
    case .script:
      "script"
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
      try validate(mapping.action, isEnabled: mapping.isEnabled)
      if let secondaryAction = mapping.secondaryAction {
        try validate(
          secondaryAction,
          isEnabled: mapping.isEnabled
        )
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
    isEnabled: Bool
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
    guard
      action.isValid
        || (!isEnabled
          && !action.scripts.isEmpty
          && action.isValid(allowingUnconfirmedScripts: true))
    else {
      throw MappingStoreError.invalidAction
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
