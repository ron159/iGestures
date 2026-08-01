import Dispatch
import Foundation
import os

public enum DiagnosticLevel: String, Codable, Sendable {
  case debug
  case info
  case warning
  case error
}

public struct DiagnosticEvent:
  Codable,
  Equatable,
  Identifiable,
  Sendable
{
  public let id: UUID
  public let timestamp: Date
  public let sessionID: UUID
  public let sequenceNumber: UInt64
  public let traceID: UUID?
  public let level: DiagnosticLevel
  public let category: String
  public let name: String
  public let metadata: [String: String]

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    sessionID: UUID,
    sequenceNumber: UInt64,
    traceID: UUID? = nil,
    level: DiagnosticLevel,
    category: String,
    name: String,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.timestamp = timestamp
    self.sessionID = sessionID
    self.sequenceNumber = sequenceNumber
    self.traceID = traceID
    self.level = level
    self.category = category
    self.name = name
    self.metadata = metadata
  }
}

public struct DiagnosticPermissionSummary: Codable, Equatable, Sendable {
  public let accessibility: Bool
  public let inputMonitoring: Bool
  public let eventPosting: Bool

  public init(
    accessibility: Bool,
    inputMonitoring: Bool,
    eventPosting: Bool
  ) {
    self.accessibility = accessibility
    self.inputMonitoring = inputMonitoring
    self.eventPosting = eventPosting
  }
}

public struct DiagnosticSettingsSummary: Codable, Equatable, Sendable {
  public let recognitionEnabled: Bool
  public let overlayEnabled: Bool
  public let feedbackEnabled: Bool
  public let hapticFeedbackEnabled: Bool
  public let trackpadGestureEnabled: Bool
  public let diagnosticPersistenceEnabled: Bool
  public let recognitionSensitivity: String
  public let primaryTrigger: String
  public let hasSecondaryTrigger: Bool
  public let mappingCount: Int
  public let applicationExclusionCount: Int
  public let applicationGroupCount: Int

  public init(
    recognitionEnabled: Bool,
    overlayEnabled: Bool,
    feedbackEnabled: Bool,
    hapticFeedbackEnabled: Bool,
    trackpadGestureEnabled: Bool,
    diagnosticPersistenceEnabled: Bool,
    recognitionSensitivity: String,
    primaryTrigger: String,
    hasSecondaryTrigger: Bool,
    mappingCount: Int,
    applicationExclusionCount: Int,
    applicationGroupCount: Int
  ) {
    self.recognitionEnabled = recognitionEnabled
    self.overlayEnabled = overlayEnabled
    self.feedbackEnabled = feedbackEnabled
    self.hapticFeedbackEnabled = hapticFeedbackEnabled
    self.trackpadGestureEnabled = trackpadGestureEnabled
    self.diagnosticPersistenceEnabled = diagnosticPersistenceEnabled
    self.recognitionSensitivity = recognitionSensitivity
    self.primaryTrigger = primaryTrigger
    self.hasSecondaryTrigger = hasSecondaryTrigger
    self.mappingCount = mappingCount
    self.applicationExclusionCount = applicationExclusionCount
    self.applicationGroupCount = applicationGroupCount
  }
}

public struct DiagnosticReportContext: Codable, Equatable, Sendable {
  public let applicationVersion: String
  public let buildNumber: String
  public let bundleIdentifier: String
  public let operatingSystem: String
  public let architecture: String
  public let eventTapState: String
  public let permissions: DiagnosticPermissionSummary
  public let settings: DiagnosticSettingsSummary

  public init(
    applicationVersion: String,
    buildNumber: String,
    bundleIdentifier: String,
    operatingSystem: String,
    architecture: String,
    eventTapState: String,
    permissions: DiagnosticPermissionSummary,
    settings: DiagnosticSettingsSummary
  ) {
    self.applicationVersion = applicationVersion
    self.buildNumber = buildNumber
    self.bundleIdentifier = bundleIdentifier
    self.operatingSystem = operatingSystem
    self.architecture = architecture
    self.eventTapState = eventTapState
    self.permissions = permissions
    self.settings = settings
  }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let generatedAt: Date
  public let context: DiagnosticReportContext
  public let events: [DiagnosticEvent]

  public init(
    generatedAt: Date = Date(),
    context: DiagnosticReportContext,
    events: [DiagnosticEvent]
  ) {
    self.schemaVersion = Self.currentSchemaVersion
    self.generatedAt = generatedAt
    self.context = context
    self.events = events
  }
}

public final class DiagnosticLogger: @unchecked Sendable {
  public static let defaultMemoryCapacity = 500
  public static let defaultMaximumFileSize = 2 * 1_024 * 1_024
  public static let defaultMaximumArchivedFiles = 4
  public static let defaultRetentionInterval: TimeInterval = 7 * 24 * 60 * 60

  public let sessionID: UUID

  private let unifiedLogger: Logger
  private let queue: DispatchQueue
  private let sequenceLock = NSLock()
  private let memoryCapacity: Int
  private let fileStore: DiagnosticLogFileStore?
  private var events: [DiagnosticEvent] = []
  private var persistenceEnabled: Bool
  private var nextSequenceNumber: UInt64 = 0

  public init(
    subsystem: String,
    directoryURL: URL?,
    persistenceEnabled: Bool,
    sessionID: UUID = UUID(),
    memoryCapacity: Int = defaultMemoryCapacity,
    maximumFileSize: Int = defaultMaximumFileSize,
    maximumArchivedFiles: Int = defaultMaximumArchivedFiles,
    retentionInterval: TimeInterval = defaultRetentionInterval
  ) {
    self.sessionID = sessionID
    self.unifiedLogger = Logger(
      subsystem: subsystem,
      category: "Diagnostics"
    )
    self.queue = DispatchQueue(label: "\(subsystem).diagnostics")
    self.memoryCapacity = max(1, memoryCapacity)
    self.persistenceEnabled = persistenceEnabled
    self.fileStore = directoryURL.map {
      DiagnosticLogFileStore(
        directoryURL: $0,
        maximumFileSize: maximumFileSize,
        maximumArchivedFiles: maximumArchivedFiles,
        retentionInterval: retentionInterval
      )
    }
  }

  public static func live(
    bundleIdentifier: String,
    persistenceEnabled: Bool
  ) -> DiagnosticLogger {
    let baseURL = try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directoryURL = baseURL?
      .appendingPathComponent(bundleIdentifier, isDirectory: true)
      .appendingPathComponent("Logs", isDirectory: true)
    return DiagnosticLogger(
      subsystem: bundleIdentifier,
      directoryURL: directoryURL,
      persistenceEnabled: persistenceEnabled
    )
  }

  public func record(
    level: DiagnosticLevel = .info,
    category: String,
    name: String,
    traceID: UUID? = nil,
    metadata: [String: String] = [:]
  ) {
    sequenceLock.lock()
    let sequenceNumber = nextSequenceNumber
    nextSequenceNumber &+= 1
    sequenceLock.unlock()
    let event = DiagnosticEvent(
      sessionID: sessionID,
      sequenceNumber: sequenceNumber,
      traceID: traceID,
      level: level,
      category: category,
      name: name,
      metadata: metadata
    )
    writeToUnifiedLog(event)
    queue.async { [self] in
      events.append(event)
      if events.count > memoryCapacity {
        events.removeFirst(events.count - memoryCapacity)
      }
      guard persistenceEnabled, let fileStore else { return }
      do {
        try fileStore.append(event)
      } catch {
        unifiedLogger.error("diagnostics.persistence_failed")
      }
    }
  }

  public func setPersistenceEnabled(_ enabled: Bool) {
    queue.sync { [self] in
      let wasEnabled = persistenceEnabled
      persistenceEnabled = enabled
      if enabled, !wasEnabled, let fileStore {
        do {
          for event in events {
            try fileStore.append(event)
          }
        } catch {
          unifiedLogger.error("diagnostics.persistence_failed")
        }
      } else if !enabled {
        try? fileStore?.clear()
      }
    }
  }

  public func clear() {
    queue.sync { [self] in
      events = []
      try? fileStore?.clear()
    }
  }

  public func exportReport(
    to destinationURL: URL,
    context: DiagnosticReportContext
  ) throws {
    try queue.sync {
      let persistedEvents = try fileStore?.loadEvents() ?? []
      var eventsByID = Dictionary(
        uniqueKeysWithValues: persistedEvents.map { ($0.id, $0) }
      )
      for event in events {
        eventsByID[event.id] = event
      }
      let report = DiagnosticReport(
        context: context,
        events: eventsByID.values.sorted {
          if $0.timestamp != $1.timestamp {
            return $0.timestamp < $1.timestamp
          }
          if $0.sessionID == $1.sessionID {
            return $0.sequenceNumber < $1.sequenceNumber
          }
          return $0.sessionID.uuidString < $1.sessionID.uuidString
        }
      )
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [
        .prettyPrinted,
        .sortedKeys,
        .withoutEscapingSlashes,
      ]
      try encoder.encode(report).write(
        to: destinationURL,
        options: .atomic
      )
    }
  }

  private func writeToUnifiedLog(_ event: DiagnosticEvent) {
    let trace = event.traceID?.uuidString ?? "-"
    switch event.level {
    case .debug:
      unifiedLogger.debug(
        "\(event.category, privacy: .public).\(event.name, privacy: .public) trace=\(trace, privacy: .public)"
      )
    case .info:
      unifiedLogger.info(
        "\(event.category, privacy: .public).\(event.name, privacy: .public) trace=\(trace, privacy: .public)"
      )
    case .warning:
      unifiedLogger.warning(
        "\(event.category, privacy: .public).\(event.name, privacy: .public) trace=\(trace, privacy: .public)"
      )
    case .error:
      unifiedLogger.error(
        "\(event.category, privacy: .public).\(event.name, privacy: .public) trace=\(trace, privacy: .public)"
      )
    }
  }
}

private final class DiagnosticLogFileStore {
  private static let currentFileName = "diagnostics.jsonl"

  private let directoryURL: URL
  private let maximumFileSize: Int
  private let maximumArchivedFiles: Int
  private let retentionInterval: TimeInterval
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    directoryURL: URL,
    maximumFileSize: Int,
    maximumArchivedFiles: Int,
    retentionInterval: TimeInterval,
    fileManager: FileManager = .default
  ) {
    self.directoryURL = directoryURL
    self.maximumFileSize = max(256, maximumFileSize)
    self.maximumArchivedFiles = max(0, maximumArchivedFiles)
    self.retentionInterval = max(0, retentionInterval)
    self.fileManager = fileManager
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    decoder.dateDecodingStrategy = .iso8601
  }

  func append(_ event: DiagnosticEvent) throws {
    try ensureDirectoryExists()
    try removeExpiredFiles()
    var line = try encoder.encode(event)
    line.append(0x0A)
    try rotateIfNeeded(adding: line.count)
    let currentURL = currentFileURL
    if !fileManager.fileExists(atPath: currentURL.path) {
      guard
        fileManager.createFile(
          atPath: currentURL.path,
          contents: nil
        )
      else {
        throw CocoaError(.fileWriteUnknown)
      }
      try fileManager.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: currentURL.path
      )
    }
    let handle = try FileHandle(forWritingTo: currentURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
  }

  func loadEvents() throws -> [DiagnosticEvent] {
    try removeExpiredFiles()
    var result: [DiagnosticEvent] = []
    for url in logFileURLsOldestFirst
    where fileManager.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      for line in data.split(separator: 0x0A) {
        if let event = try? decoder.decode(
          DiagnosticEvent.self,
          from: Data(line)
        ) {
          result.append(event)
        }
      }
    }
    return result
  }

  func clear() throws {
    for url in knownLogFileURLs
    where fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  private var currentFileURL: URL {
    directoryURL.appendingPathComponent(
      Self.currentFileName,
      isDirectory: false
    )
  }

  private func archivedFileURL(_ index: Int) -> URL {
    directoryURL.appendingPathComponent(
      "diagnostics.\(index).jsonl",
      isDirectory: false
    )
  }

  private var knownLogFileURLs: [URL] {
    [currentFileURL]
      + (1...max(1, maximumArchivedFiles)).compactMap {
        $0 <= maximumArchivedFiles ? archivedFileURL($0) : nil
      }
  }

  private var logFileURLsOldestFirst: [URL] {
    (1...max(1, maximumArchivedFiles)).reversed().compactMap {
      $0 <= maximumArchivedFiles ? archivedFileURL($0) : nil
    } + [currentFileURL]
  }

  private func ensureDirectoryExists() throws {
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directoryURL.path
    )
  }

  private func rotateIfNeeded(adding byteCount: Int) throws {
    guard fileManager.fileExists(atPath: currentFileURL.path) else {
      return
    }
    let attributes = try fileManager.attributesOfItem(
      atPath: currentFileURL.path
    )
    let currentSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
    guard currentSize + byteCount > maximumFileSize else { return }

    if maximumArchivedFiles == 0 {
      try fileManager.removeItem(at: currentFileURL)
      return
    }
    for index in stride(
      from: maximumArchivedFiles,
      through: 1,
      by: -1
    ) {
      let destination = archivedFileURL(index)
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      let source =
        index == 1
        ? currentFileURL
        : archivedFileURL(index - 1)
      if fileManager.fileExists(atPath: source.path) {
        try fileManager.moveItem(at: source, to: destination)
      }
    }
  }

  private func removeExpiredFiles(now: Date = Date()) throws {
    guard retentionInterval > 0 else { return }
    for url in knownLogFileURLs
    where fileManager.fileExists(atPath: url.path) {
      let attributes = try fileManager.attributesOfItem(
        atPath: url.path
      )
      guard let modifiedAt = attributes[.modificationDate] as? Date,
        now.timeIntervalSince(modifiedAt) > retentionInterval
      else {
        continue
      }
      try fileManager.removeItem(at: url)
    }
  }
}
