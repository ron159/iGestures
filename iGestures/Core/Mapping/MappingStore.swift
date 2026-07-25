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
  case invalidShortcut
  case invalidTemplateCount(limit: Int)
  case invalidTemplatePointCount(required: Int)
  case nonFiniteTemplate
  case tooManyBundleIDs(limit: Int)
  case invalidBundleID
  case invalidData
  case recoveryFailed
  case fileSystemFailure
}

public actor MappingStore {
  public static let defaultFileName = "gesture-mappings.json"
  public static let defaultBackupFileName =
    "gesture-mappings.backup.json"

  public nonisolated let fileURL: URL
  public nonisolated let backupURL: URL
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
    try replaceWithImportedData(readData(at: sourceURL))
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
      let isCanonicalEmptyShortcut =
        mapping.shortcut == ShortcutRecordingSession.emptyShortcut
      let isCanonicalRecordedShortcut =
        mapping.shortcut.isValid
        && mapping.shortcut.modifiers
          == ShortcutRecordingSession.normalizedModifiers(
            mapping.shortcut.modifiers
          )
      guard
        isCanonicalRecordedShortcut
          || (!mapping.isEnabled && isCanonicalEmptyShortcut)
      else {
        throw MappingStoreError.invalidShortcut
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
  }

  private nonisolated func validate(_ scope: AppScope) throws {
    let bundleIDs: [String]
    switch scope {
    case .all:
      return
    case .only(let values), .allExcept(let values):
      bundleIDs = values
    }

    guard bundleIDs.count <= limits.maximumBundleIDsPerScope else {
      throw MappingStoreError.tooManyBundleIDs(
        limit: limits.maximumBundleIDsPerScope
      )
    }
    guard
      bundleIDs.allSatisfy({
        !$0.isEmpty && $0.utf8.count <= limits.maximumBundleIDLength
      })
    else {
      throw MappingStoreError.invalidBundleID
    }
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
