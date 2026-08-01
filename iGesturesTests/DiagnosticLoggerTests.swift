import Foundation
import XCTest

@testable import iGestures

final class DiagnosticLoggerTests: XCTestCase {
  func testExportContainsStructuredEventsAndContext() throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let logger = DiagnosticLogger(
      subsystem: "com.ron159.igestures.tests",
      directoryURL: directoryURL,
      persistenceEnabled: false,
      sessionID: UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
      )!
    )
    let traceID = UUID(
      uuidString: "00000000-0000-0000-0000-000000000002"
    )!
    logger.record(
      level: .warning,
      category: "recognition",
      name: "ambiguous",
      traceID: traceID,
      metadata: [
        "best_distance": "0.1200",
        "second_distance": "0.1300",
      ]
    )

    let reportURL = directoryURL.appendingPathComponent("report.json")
    try logger.exportReport(to: reportURL, context: reportContext)
    let report = try decodeReport(at: reportURL)

    XCTAssertEqual(report.schemaVersion, 1)
    XCTAssertEqual(report.context.applicationVersion, "1.0")
    XCTAssertEqual(report.events.count, 1)
    XCTAssertEqual(report.events[0].traceID, traceID)
    XCTAssertEqual(report.events[0].category, "recognition")
    XCTAssertEqual(report.events[0].name, "ambiguous")
    XCTAssertEqual(
      report.events[0].metadata["best_distance"],
      "0.1200"
    )
  }

  func testPersistenceRequiresOptInAndDisablingClearsFiles() throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let subsystem = "com.ron159.igestures.persistence-tests"
    let logger = DiagnosticLogger(
      subsystem: subsystem,
      directoryURL: directoryURL,
      persistenceEnabled: false
    )

    logger.record(category: "lifecycle", name: "memory_only")
    try logger.exportReport(
      to: directoryURL.appendingPathComponent("memory.json"),
      context: reportContext
    )

    let beforeOptIn = DiagnosticLogger(
      subsystem: subsystem,
      directoryURL: directoryURL,
      persistenceEnabled: false
    )
    let beforeURL = directoryURL.appendingPathComponent("before.json")
    try beforeOptIn.exportReport(to: beforeURL, context: reportContext)
    XCTAssertTrue(try decodeReport(at: beforeURL).events.isEmpty)

    logger.setPersistenceEnabled(true)
    logger.record(category: "lifecycle", name: "persisted")
    try logger.exportReport(
      to: directoryURL.appendingPathComponent("enabled.json"),
      context: reportContext
    )

    let afterOptIn = DiagnosticLogger(
      subsystem: subsystem,
      directoryURL: directoryURL,
      persistenceEnabled: true
    )
    let afterURL = directoryURL.appendingPathComponent("after.json")
    try afterOptIn.exportReport(to: afterURL, context: reportContext)
    XCTAssertEqual(
      try decodeReport(at: afterURL).events.map(\.name),
      ["memory_only", "persisted"]
    )

    logger.setPersistenceEnabled(false)
    try logger.exportReport(
      to: directoryURL.appendingPathComponent("disabled.json"),
      context: reportContext
    )
    let afterDisabling = DiagnosticLogger(
      subsystem: subsystem,
      directoryURL: directoryURL,
      persistenceEnabled: false
    )
    let clearedURL = directoryURL.appendingPathComponent("cleared.json")
    try afterDisabling.exportReport(
      to: clearedURL,
      context: reportContext
    )
    XCTAssertTrue(try decodeReport(at: clearedURL).events.isEmpty)
  }

  func testFileRotationKeepsStorageBounded() throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let subsystem = "com.ron159.igestures.rotation-tests"
    let logger = DiagnosticLogger(
      subsystem: subsystem,
      directoryURL: directoryURL,
      persistenceEnabled: true,
      maximumFileSize: 256,
      maximumArchivedFiles: 2
    )

    for index in 0..<12 {
      logger.record(
        category: "rotation",
        name: "event_\(index)",
        metadata: ["value": String(repeating: "x", count: 80)]
      )
    }
    try logger.exportReport(
      to: directoryURL.appendingPathComponent("rotation.json"),
      context: reportContext
    )

    let logFiles = try FileManager.default
      .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jsonl" }
    XCTAssertEqual(logFiles.count, 3)

    let reloaded = DiagnosticLogger(
      subsystem: subsystem,
      directoryURL: directoryURL,
      persistenceEnabled: true,
      maximumFileSize: 256,
      maximumArchivedFiles: 2
    )
    let reportURL = directoryURL.appendingPathComponent("reloaded.json")
    try reloaded.exportReport(to: reportURL, context: reportContext)
    let persistedEvents = try decodeReport(at: reportURL).events
    XCTAssertGreaterThan(persistedEvents.count, 0)
    XCTAssertLessThanOrEqual(persistedEvents.count, 3)
  }

  func testExpiredLogFilesAreRemoved() throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let subsystem = "com.ron159.igestures.retention-tests"
    let logger = DiagnosticLogger(
      subsystem: subsystem,
      directoryURL: directoryURL,
      persistenceEnabled: true,
      retentionInterval: 1
    )
    logger.record(category: "lifecycle", name: "expired")
    try logger.exportReport(
      to: directoryURL.appendingPathComponent("initial.json"),
      context: reportContext
    )
    let currentLogURL = directoryURL.appendingPathComponent(
      "diagnostics.jsonl"
    )
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -10)],
      ofItemAtPath: currentLogURL.path
    )

    let reloaded = DiagnosticLogger(
      subsystem: subsystem,
      directoryURL: directoryURL,
      persistenceEnabled: true,
      retentionInterval: 1
    )
    let reportURL = directoryURL.appendingPathComponent("expired.json")
    try reloaded.exportReport(to: reportURL, context: reportContext)

    XCTAssertTrue(try decodeReport(at: reportURL).events.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: currentLogURL.path))
  }

  private var reportContext: DiagnosticReportContext {
    DiagnosticReportContext(
      applicationVersion: "1.0",
      buildNumber: "1",
      bundleIdentifier: "com.ron159.igestures.tests",
      operatingSystem: "macOS Test",
      architecture: "arm64",
      eventTapState: "running",
      permissions: DiagnosticPermissionSummary(
        accessibility: true,
        inputMonitoring: true,
        eventPosting: true
      ),
      settings: DiagnosticSettingsSummary(
        recognitionEnabled: true,
        overlayEnabled: true,
        feedbackEnabled: true,
        hapticFeedbackEnabled: false,
        trackpadGestureEnabled: false,
        diagnosticPersistenceEnabled: true,
        recognitionSensitivity: "standard",
        primaryTrigger: "right_mouse",
        hasSecondaryTrigger: false,
        mappingCount: 4,
        applicationExclusionCount: 0,
        applicationGroupCount: 1
      )
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
    return url
  }

  private func decodeReport(at url: URL) throws -> DiagnosticReport {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      DiagnosticReport.self,
      from: Data(contentsOf: url)
    )
  }
}
