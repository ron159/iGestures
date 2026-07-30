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
