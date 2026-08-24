import AppKit
import CryptoKit
import Foundation
import XCTest

@testable import iGestures

final class AppPreferencesStoreTests: XCTestCase {
  @MainActor
  func testDefaultsEnableRecognitionAndOverlay() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let store = AppPreferencesStore(userDefaults: userDefaults)

    XCTAssertTrue(store.recognitionEnabled)
    XCTAssertTrue(store.overlayEnabled)
    XCTAssertFalse(store.scriptExecutionNoticeAcknowledged)
    XCTAssertNil(store.trailColor)
    XCTAssertEqual(store.interfaceAppearance, .system)
    XCTAssertEqual(store.interfaceLanguage, .system)
    XCTAssertEqual(store.applicationIcon, .systemDefault)
    XCTAssertEqual(store.triggerButton, .right)
    XCTAssertNil(store.secondaryTriggerButton)
    XCTAssertEqual(
      store.triggerDuration,
      GestureInputConfiguration.defaultTriggerDuration
    )
  }

  @MainActor
  func testValuesPersistAcrossStoreInstances() throws {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let store = AppPreferencesStore(userDefaults: userDefaults)
    store.setRecognitionEnabled(false)
    store.setOverlayEnabled(false)
    let trailColor = try XCTUnwrap(
      GestureTrailColor(red: 0.2, green: 0.4, blue: 0.8)
    )
    store.setTrailColor(trailColor)
    store.setInterfaceAppearance(.dark)
    store.setInterfaceLanguage(.simplifiedChinese)
    store.setApplicationIcon(.gestureThinker)
    store.setTriggerButton(
      GestureTriggerButton(buttonNumber: 7)
    )
    store.setSecondaryTriggerButton(
      GestureTriggerButton(buttonNumber: 8)
    )
    store.setTriggerDuration(0.35)
    store.setScriptExecutionNoticeAcknowledged(true)
    store.setGestureSidebarGroups(["Browser", "  Work  ", "Browser"])
    store.setGestureSidebarApplications([
      "com.apple.Safari",
      " com.apple.finder ",
      "com.apple.Safari",
    ])

    let reloaded = AppPreferencesStore(userDefaults: userDefaults)
    XCTAssertFalse(reloaded.recognitionEnabled)
    XCTAssertFalse(reloaded.overlayEnabled)
    XCTAssertEqual(reloaded.trailColor, trailColor)
    XCTAssertEqual(reloaded.interfaceAppearance, .dark)
    XCTAssertEqual(reloaded.interfaceLanguage, .simplifiedChinese)
    XCTAssertEqual(reloaded.applicationIcon, .gestureThinker)
    XCTAssertEqual(
      userDefaults.stringArray(forKey: "AppleLanguages"),
      ["zh-Hans"]
    )
    XCTAssertEqual(
      reloaded.triggerButton,
      GestureTriggerButton(buttonNumber: 7)
    )
    XCTAssertEqual(
      reloaded.secondaryTriggerButton,
      GestureTriggerButton(buttonNumber: 8)
    )
    XCTAssertEqual(reloaded.triggerDuration, 0.35)
    XCTAssertTrue(reloaded.scriptExecutionNoticeAcknowledged)
    XCTAssertEqual(reloaded.gestureSidebarGroups, ["Browser", "Work"])
    XCTAssertEqual(
      reloaded.gestureSidebarApplications,
      ["com.apple.finder", "com.apple.Safari"]
    )

    reloaded.clearGestureSidebarConfiguration()
    XCTAssertTrue(reloaded.gestureSidebarGroups.isEmpty)
    XCTAssertTrue(reloaded.gestureSidebarApplications.isEmpty)
  }

  @MainActor
  func testConfigurationSnapshotRoundTripsUserFacingSettings()
    throws
  {
    let (sourceSuiteName, sourceDefaults) = makeUserDefaults()
    let (targetSuiteName, targetDefaults) = makeUserDefaults()
    defer {
      sourceDefaults.removePersistentDomain(forName: sourceSuiteName)
      targetDefaults.removePersistentDomain(forName: targetSuiteName)
    }
    let source = AppPreferencesStore(userDefaults: sourceDefaults)
    let target = AppPreferencesStore(userDefaults: targetDefaults)
    let trailColor = try XCTUnwrap(
      GestureTrailColor(red: 0.1, green: 0.3, blue: 0.9)
    )
    let preset = ActionPreset(
      id: "user.exported",
      name: "Exported Action",
      category: .editing,
      action: .keyboardShortcut(
        KeyboardShortcut(keyCode: 8, modifiers: 0x10_0000)
      ),
      isUserDefined: true
    )

    source.setRecognitionEnabled(false)
    source.setOverlayEnabled(false)
    source.setTrailColor(trailColor)
    source.setInterfaceAppearance(.light)
    source.setInterfaceLanguage(.english)
    source.setTriggerButton(.button4)
    source.setSecondaryTriggerButton(.button5)
    source.setTriggerDuration(0.42)
    source.setRecognitionSensitivity(.strict)
    source.setFeedbackEnabled(false)
    source.setGlobalToggleShortcut(
      KeyboardShortcut(keyCode: 12, modifiers: 0x10_0000)
    )
    source.setApplicationExclusions([
      ApplicationExclusionRule(bundleIdentifier: "com.example.app")
    ])
    source.setTrackpadGestureEnabled(true)
    source.setTrackpadModifiers(0x10_0000 | 0x8_0000)
    source.setHapticFeedbackEnabled(true)
    source.setDiagnosticPersistenceEnabled(true)
    source.setCustomActionPresets([preset])
    source.setFavoriteActionPresetIDs([preset.id])
    source.setRecentActionPresetIDs([preset.id])
    let snapshot = source.configurationSnapshot(
      launchAtLoginEnabled: true
    )

    target.applyConfigurationSnapshot(snapshot)

    XCTAssertEqual(
      target.configurationSnapshot(launchAtLoginEnabled: true),
      snapshot
    )
    XCTAssertEqual(
      targetDefaults.stringArray(forKey: "AppleLanguages"),
      ["en"]
    )
  }

  @MainActor
  func testInvalidTrailColorIsIgnored() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    userDefaults.set(
      Data(#"{"red":2,"green":0.5,"blue":0.5}"#.utf8),
      forKey: "general.trail-color"
    )

    let store = AppPreferencesStore(userDefaults: userDefaults)

    XCTAssertNil(store.trailColor)
  }

  @MainActor
  func testInvalidInputConfigurationFallsBackToSafeValues() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    userDefaults.set(-1, forKey: "general.trigger-button")
    userDefaults.set(1, forKey: "general.secondary-trigger-button")
    userDefaults.set(100, forKey: "general.trigger-duration")

    let store = AppPreferencesStore(userDefaults: userDefaults)

    XCTAssertEqual(store.triggerButton, .right)
    XCTAssertNil(store.secondaryTriggerButton)
    XCTAssertEqual(
      store.triggerDuration,
      GestureInputConfiguration.maximumTriggerDuration
    )
  }

  @MainActor
  func testInvalidApplicationIconFallsBackToDefault() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    userDefaults.set(
      "missing-icon",
      forKey: "general.application-icon"
    )

    let store = AppPreferencesStore(userDefaults: userDefaults)

    XCTAssertEqual(store.applicationIcon, .systemDefault)
  }

  @MainActor
  func testSecondaryTriggerCannotMatchPrimaryOrTrackpad() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let store = AppPreferencesStore(userDefaults: userDefaults)

    store.setSecondaryTriggerButton(.right)
    XCTAssertNil(store.secondaryTriggerButton)

    store.setSecondaryTriggerButton(.trackpad)
    XCTAssertNil(store.secondaryTriggerButton)

    store.setSecondaryTriggerButton(.button4)
    XCTAssertEqual(store.secondaryTriggerButton, .button4)

    store.setSecondaryTriggerButton(nil)
    XCTAssertNil(store.secondaryTriggerButton)
  }

  @MainActor
  func testKeyboardTriggersPersistAcrossStoreInstances() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let store = AppPreferencesStore(userDefaults: userDefaults)
    let primary = GestureTriggerButton.keyboard(keyCode: 49)
    let secondary = GestureTriggerButton.keyboard(keyCode: 36)

    store.setTriggerButton(primary)
    store.setSecondaryTriggerButton(secondary)

    let reloaded = AppPreferencesStore(userDefaults: userDefaults)
    XCTAssertEqual(reloaded.triggerButton, primary)
    XCTAssertEqual(reloaded.triggerButton.keyboardKeyCode, 49)
    XCTAssertEqual(reloaded.secondaryTriggerButton, secondary)
    XCTAssertEqual(reloaded.secondaryTriggerButton?.keyboardKeyCode, 36)
  }

  @MainActor
  func testDiagnosticsPersistOnlyAfterExplicitOptIn() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let records = [
      GestureDiagnosticRecord(
        outcome: .executed,
        mappingName: "Back"
      )
    ]
    let store = AppPreferencesStore(userDefaults: userDefaults)

    store.setDiagnosticRecords(records)
    XCTAssertTrue(store.diagnosticRecords.isEmpty)

    store.setDiagnosticPersistenceEnabled(true)
    store.setDiagnosticRecords(records)
    XCTAssertEqual(store.diagnosticRecords, records)

    store.setDiagnosticPersistenceEnabled(false)
    XCTAssertTrue(store.diagnosticRecords.isEmpty)
  }

  @MainActor
  func testActionPresetPreferencesPersistAndNormalize() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let store = AppPreferencesStore(userDefaults: userDefaults)
    let preset = ActionPreset(
      id: "user.test",
      name: "My Copy",
      category: .editing,
      action: .keyboardShortcut(
        KeyboardShortcut(keyCode: 8, modifiers: 0x10_0000)
      ),
      isUserDefined: true
    )

    store.setCustomActionPresets([preset, preset])
    store.setFavoriteActionPresetIDs(["user.test", "browser.back"])
    store.setRecentActionPresetIDs([
      "browser.back",
      "user.test",
      "browser.back",
    ])

    let reloaded = AppPreferencesStore(userDefaults: userDefaults)
    XCTAssertEqual(reloaded.customActionPresets, [preset])
    XCTAssertEqual(
      reloaded.favoriteActionPresetIDs,
      Set(["user.test", "browser.back"])
    )
    XCTAssertEqual(
      reloaded.recentActionPresetIDs,
      ["browser.back", "user.test"]
    )
  }

  func testUpdateManifestRequiresValidSignature() async throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let unsigned = UpdateManifest(
      version: "1.1.0",
      minimumSystemVersion: "26.0",
      archiveURL: try XCTUnwrap(
        URL(string: "https://example.com/iGestures.zip")
      ),
      sha256: String(repeating: "a", count: 64),
      signature: ""
    )
    let signature = try privateKey.signature(
      for: unsigned.signedPayload
    )
    let manifest = UpdateManifest(
      version: unsigned.version,
      minimumSystemVersion: unsigned.minimumSystemVersion,
      archiveURL: unsigned.archiveURL,
      sha256: unsigned.sha256,
      signature: signature.base64EncodedString()
    )
    let service = try XCTUnwrap(
      UpdateService(
        currentVersion: "1.0.0",
        publicKeyBase64:
          privateKey.publicKey.rawRepresentation.base64EncodedString()
      )
    )

    let validResult = await service.validate(
      manifestData: try JSONEncoder().encode(manifest)
    )
    XCTAssertEqual(
      validResult,
      .available(VerifiedUpdate(manifest: manifest))
    )

    let tampered = UpdateManifest(
      version: "1.2.0",
      minimumSystemVersion: manifest.minimumSystemVersion,
      archiveURL: manifest.archiveURL,
      sha256: manifest.sha256,
      signature: manifest.signature
    )
    let rejectedResult = await service.validate(
      manifestData: try JSONEncoder().encode(tampered)
    )
    XCTAssertEqual(rejectedResult, .rejected(.invalidSignature))
  }

  func testGitHubReleaseServiceDetectsNewerStableRelease() async throws {
    let service = try XCTUnwrap(
      GitHubReleaseService(
        currentVersion: "0.3.0",
        latestReleaseURL: try XCTUnwrap(
          URL(
            string:
              "https://api.github.com/repos/ron159/iGestures/releases/latest"
          )
        )
      )
    )
    let releaseURL = try XCTUnwrap(
      URL(
        string:
          "https://github.com/ron159/iGestures/releases/tag/v0.4.0"
      )
    )
    let data = Data(
      """
      {
        "tag_name": "v0.4.0",
        "html_url": "\(releaseURL.absoluteString)",
        "draft": false,
        "prerelease": false
      }
      """.utf8
    )

    let result = await service.validate(releaseData: data)

    XCTAssertEqual(
      result,
      .available(
        GitHubRelease(version: "0.4.0", pageURL: releaseURL)
      )
    )
  }

  func testGitHubReleaseServiceFindsVersionedDiskImage() async throws {
    let service = try XCTUnwrap(
      GitHubReleaseService(
        currentVersion: "0.3.0",
        latestReleaseURL: try XCTUnwrap(
          URL(
            string:
              "https://api.github.com/repos/ron159/iGestures/releases/latest"
          )
        )
      )
    )
    let releaseURL = try XCTUnwrap(
      URL(
        string:
          "https://github.com/ron159/iGestures/releases/tag/v0.4.0"
      )
    )
    let archiveURL = try XCTUnwrap(
      URL(
        string:
          "https://github.com/ron159/iGestures/releases/download/v0.4.0/iGestures-0.4.0-macOS-arm64.dmg"
      )
    )
    let checksumURL = try XCTUnwrap(
      URL(
        string:
          "https://github.com/ron159/iGestures/releases/download/v0.4.0/iGestures-0.4.0-macOS-arm64.dmg.sha256"
      )
    )
    let data = Data(
      """
      {
        "tag_name": "v0.4.0",
        "html_url": "\(releaseURL.absoluteString)",
        "draft": false,
        "prerelease": false,
        "assets": [
          {
            "name": "iGestures-0.4.0-macOS-arm64.dmg",
            "browser_download_url": "\(archiveURL.absoluteString)",
            "size": 123456
          },
          {
            "name": "iGestures-0.4.0-macOS-arm64.dmg.sha256",
            "browser_download_url": "\(checksumURL.absoluteString)",
            "size": 112
          }
        ]
      }
      """.utf8
    )

    let result = await service.validate(releaseData: data)

    XCTAssertEqual(
      result,
      .available(
        GitHubRelease(
          version: "0.4.0",
          pageURL: releaseURL,
          diskImage: GitHubReleaseDiskImage(
            name: "iGestures-0.4.0-macOS-arm64.dmg",
            downloadURL: archiveURL,
            checksumURL: checksumURL,
            byteCount: 123456
          )
        )
      )
    )
  }

  func testGitHubReleaseServiceIgnoresUntrustedDiskImageURL()
    async throws
  {
    let service = try XCTUnwrap(
      GitHubReleaseService(
        currentVersion: "0.3.0",
        latestReleaseURL: try XCTUnwrap(
          URL(
            string:
              "https://api.github.com/repos/ron159/iGestures/releases/latest"
          )
        )
      )
    )
    let releaseURL = try XCTUnwrap(
      URL(
        string:
          "https://github.com/ron159/iGestures/releases/tag/v0.4.0"
      )
    )
    let data = Data(
      """
      {
        "tag_name": "v0.4.0",
        "html_url": "\(releaseURL.absoluteString)",
        "draft": false,
        "prerelease": false,
        "assets": [
          {
            "name": "iGestures-0.4.0-macOS-arm64.dmg",
            "browser_download_url": "https://example.com/iGestures-0.4.0-macOS-arm64.dmg",
            "size": 123456
          },
          {
            "name": "iGestures-0.4.0-macOS-arm64.dmg.sha256",
            "browser_download_url": "https://github.com/ron159/iGestures/releases/download/v0.4.0/iGestures-0.4.0-macOS-arm64.dmg.sha256",
            "size": 112
          }
        ]
      }
      """.utf8
    )

    let result = await service.validate(releaseData: data)

    XCTAssertEqual(
      result,
      .available(
        GitHubRelease(version: "0.4.0", pageURL: releaseURL)
      )
    )
  }

  func testGitHubReleaseChecksumRequiresExactArchiveName() {
    let checksum = String(repeating: "a", count: 64)
    let archiveName = "iGestures-0.4.0-macOS-arm64.dmg"

    XCTAssertEqual(
      GitHubReleaseService.checksum(
        in: Data("\(checksum)  \(archiveName)\n".utf8),
        archiveName: archiveName
      ),
      checksum
    )
    XCTAssertNil(
      GitHubReleaseService.checksum(
        in: Data("\(checksum)  other.dmg\n".utf8),
        archiveName: archiveName
      )
    )
  }

  func testUpdateDownloadProgressReportsPercentageAndClampsAtCompletion() {
    let progress = UpdateDownloadProgress(
      receivedByteCount: 25,
      totalByteCount: 100
    )
    XCTAssertEqual(progress.fractionCompleted, 0.25)
    XCTAssertEqual(progress.percentage, 25)

    let completed = UpdateDownloadProgress(
      receivedByteCount: 120,
      totalByteCount: 100
    )
    XCTAssertEqual(completed.fractionCompleted, 1)
    XCTAssertEqual(completed.percentage, 100)

    let indeterminate = UpdateDownloadProgress(
      receivedByteCount: 25,
      totalByteCount: nil
    )
    XCTAssertNil(indeterminate.fractionCompleted)
    XCTAssertNil(indeterminate.percentage)
  }

  func testUpdateInstallerAcceptsMatchingAdHocSigningIdentity() {
    let identity = UpdateSigningIdentity(
      identifier: "com.ron159.igestures.dev",
      teamIdentifier: nil
    )

    XCTAssertTrue(
      UpdatePackageInstaller.isTrustedReplacement(
        current: identity,
        staged: identity,
        expectedBundleIdentifier: identity.identifier
      )
    )
  }

  func testUpdateInstallerRejectsDifferentBundleOrSigningTeam() {
    let current = UpdateSigningIdentity(
      identifier: "com.ron159.igestures.dev",
      teamIdentifier: "CURRENTTEAM"
    )

    XCTAssertFalse(
      UpdatePackageInstaller.isTrustedReplacement(
        current: current,
        staged: UpdateSigningIdentity(
          identifier: "com.example.other",
          teamIdentifier: "CURRENTTEAM"
        ),
        expectedBundleIdentifier: current.identifier
      )
    )
    XCTAssertFalse(
      UpdatePackageInstaller.isTrustedReplacement(
        current: current,
        staged: UpdateSigningIdentity(
          identifier: current.identifier,
          teamIdentifier: "OTHERTEAM"
        ),
        expectedBundleIdentifier: current.identifier
      )
    )
  }

  func testGitHubReleaseServiceHonorsSkippedVersion() async throws {
    let service = try XCTUnwrap(
      GitHubReleaseService(
        currentVersion: "0.3.0",
        latestReleaseURL: try XCTUnwrap(
          URL(
            string:
              "https://api.github.com/repos/ron159/iGestures/releases/latest"
          )
        ),
        skippedVersion: "0.4.0"
      )
    )
    let data = Data(
      """
      {
        "tag_name": "v0.4.0",
        "html_url": "https://github.com/ron159/iGestures/releases/tag/v0.4.0",
        "draft": false,
        "prerelease": false
      }
      """.utf8
    )

    let result = await service.validate(releaseData: data)

    XCTAssertEqual(result, .skipped(version: "0.4.0"))
  }

  private func makeUserDefaults() -> (String, UserDefaults) {
    let suiteName = "iGesturesTests.\(UUID().uuidString)"
    return (
      suiteName,
      UserDefaults(suiteName: suiteName)!
    )
  }
}

private final class UpdateDownloadTestURLProtocol: URLProtocol {
  private static let payload = Data(repeating: 0x61, count: 128 * 1_024)

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.scheme == "igestures-test"
  }

  override class func canonicalRequest(
    for request: URLRequest
  ) -> URLRequest {
    request
  }

  override func startLoading() {
    guard
      let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [
          "Content-Length": String(Self.payload.count)
        ]
      )
    else {
      client?.urlProtocol(
        self,
        didFailWithError: URLError(.badServerResponse)
      )
      return
    }
    client?.urlProtocol(
      self,
      didReceive: response,
      cacheStoragePolicy: .notAllowed
    )
    let midpoint = Self.payload.count / 2
    client?.urlProtocol(self, didLoad: Self.payload[..<midpoint])
    client?.urlProtocol(self, didLoad: Self.payload[midpoint...])
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class UpdateDownloadProgressRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedProgress: [UpdateDownloadProgress] = []

  func append(_ progress: UpdateDownloadProgress) {
    lock.withLock {
      recordedProgress.append(progress)
    }
  }

  var values: [UpdateDownloadProgress] {
    lock.withLock { recordedProgress }
  }
}

final class UpdateFileDownloaderTests: XCTestCase {
  func testDownloadPublishesByteProgress() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UpdateDownloadTestURLProtocol.self]
    let recorder = UpdateDownloadProgressRecorder()

    let (temporaryURL, response) = try await UpdateFileDownloader.download(
      from: try XCTUnwrap(URL(string: "igestures-test://update.dmg")),
      configuration: configuration,
      expectedByteCount: 128 * 1_024,
      progressHandler: { progress in
        recorder.append(progress)
      }
    )
    defer { try? FileManager.default.removeItem(at: temporaryURL) }

    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(
      try Data(contentsOf: temporaryURL).count,
      128 * 1_024
    )
    XCTAssertFalse(recorder.values.isEmpty)
    XCTAssertEqual(recorder.values.last?.percentage, 100)
  }
}

final class UpdatePackageInstallerTests: XCTestCase {
  func testStagesDiskImageAndReplacesAdHocSignedApplication() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
      "iGestures-update-installer-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? fileManager.removeItem(at: rootURL) }

    let currentApplicationURL = rootURL.appendingPathComponent(
      "Current/iGestures.app",
      isDirectory: true
    )
    let imageRootURL = rootURL.appendingPathComponent(
      "Image",
      isDirectory: true
    )
    let imageApplicationURL = imageRootURL.appendingPathComponent(
      "iGestures.app",
      isDirectory: true
    )
    let diskImageURL = rootURL.appendingPathComponent("Update.dmg")
    let updateDirectoryURL = rootURL.appendingPathComponent(
      "Update",
      isDirectory: true
    )
    try fileManager.createDirectory(
      at: currentApplicationURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: imageRootURL,
      withIntermediateDirectories: true
    )
    try run(
      "/usr/bin/ditto",
      [Bundle.main.bundleURL.path, currentApplicationURL.path]
    )
    try run(
      "/usr/bin/ditto",
      [Bundle.main.bundleURL.path, imageApplicationURL.path]
    )
    try run(
      "/usr/bin/codesign",
      ["--force", "--deep", "--sign", "-", currentApplicationURL.path]
    )
    try run(
      "/usr/bin/codesign",
      ["--force", "--deep", "--sign", "-", imageApplicationURL.path]
    )
    try run(
      "/usr/bin/hdiutil",
      [
        "create",
        "-srcfolder",
        imageRootURL.path,
        "-ov",
        "-format",
        "UDZO",
        diskImageURL.path,
      ]
    )

    let expectedBundle = try XCTUnwrap(Bundle(url: currentApplicationURL))
    let expectedVersion = try XCTUnwrap(
      expectedBundle.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String
    )
    let expectedIdentifier = try XCTUnwrap(
      expectedBundle.bundleIdentifier
    )
    let installer = UpdatePackageInstaller()
    let stagedApplicationURL = try await installer.stage(
      archiveURL: diskImageURL,
      in: updateDirectoryURL
    )
    let installedApplicationURL = try await installer.install(
      stagedApplicationURL: stagedApplicationURL,
      currentApplicationURL: currentApplicationURL,
      expectedVersion: expectedVersion,
      expectedBundleIdentifier: expectedIdentifier
    )

    XCTAssertEqual(installedApplicationURL, currentApplicationURL)
    XCTAssertTrue(
      fileManager.fileExists(atPath: installedApplicationURL.path)
    )
    try run(
      "/usr/bin/codesign",
      ["--verify", "--deep", "--strict", installedApplicationURL.path]
    )
  }

  private func run(
    _ executablePath: String,
    _ arguments: [String]
  ) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(
      process.terminationStatus,
      0,
      "\(executablePath) failed with status \(process.terminationStatus)"
    )
  }
}

final class ApplicationIconServiceTests: XCTestCase {
  @MainActor
  func testAppliesCustomIconAndRestoresDefault() {
    let defaultImage = NSImage(size: NSSize(width: 32, height: 32))
    let customImage = NSImage(size: NSSize(width: 64, height: 64))
    var appliedImage: NSImage?
    var applyCount = 0
    var loadCount = 0
    let service = ApplicationIconService(
      defaultIconImage: defaultImage,
      imageLoader: { resourceName in
        loadCount += 1
        return resourceName == "AppIcon-GestureRunner"
          ? customImage
          : nil
      },
      applyImage: { image in
        appliedImage = image
        applyCount += 1
      }
    )

    XCTAssertTrue(service.apply(.gestureRunner))
    XCTAssertTrue(appliedImage === customImage)
    XCTAssertTrue(service.image(for: .gestureRunner) === customImage)
    XCTAssertEqual(loadCount, 1)
    XCTAssertTrue(service.image(for: .systemDefault) === defaultImage)

    XCTAssertTrue(service.apply(.systemDefault))
    XCTAssertNil(appliedImage)
    XCTAssertEqual(applyCount, 2)
  }

  @MainActor
  func testMissingCustomIconDoesNotReplaceCurrentIcon() {
    let defaultImage = NSImage(size: NSSize(width: 32, height: 32))
    var applyCount = 0
    let service = ApplicationIconService(
      defaultIconImage: defaultImage,
      imageLoader: { _ in nil },
      applyImage: { _ in applyCount += 1 }
    )

    XCTAssertFalse(service.apply(.purpleMouse))
    XCTAssertEqual(applyCount, 0)
  }

  @MainActor
  func testAlternateIconResourcesAreBundledAndLoadable() throws {
    let bundle = Bundle(for: ApplicationIconService.self)

    for icon in ApplicationIconChoice.allCases {
      guard let resourceName = icon.resourceName else { continue }
      let resourceURL = try XCTUnwrap(
        bundle.url(
          forResource: resourceName,
          withExtension: "icns"
        )
      )
      XCTAssertNotNil(NSImage(contentsOf: resourceURL))
    }
  }
}
