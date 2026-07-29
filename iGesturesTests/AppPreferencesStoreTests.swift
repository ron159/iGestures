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
    XCTAssertEqual(store.triggerButton, .right)
    XCTAssertEqual(
      store.triggerDuration,
      GestureInputConfiguration.defaultTriggerDuration
    )
  }

  @MainActor
  func testValuesPersistAcrossStoreInstances() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let store = AppPreferencesStore(userDefaults: userDefaults)
    store.setRecognitionEnabled(false)
    store.setOverlayEnabled(false)
    store.setTriggerButton(
      GestureTriggerButton(buttonNumber: 7)
    )
    store.setTriggerDuration(0.35)

    let reloaded = AppPreferencesStore(userDefaults: userDefaults)
    XCTAssertFalse(reloaded.recognitionEnabled)
    XCTAssertFalse(reloaded.overlayEnabled)
    XCTAssertEqual(
      reloaded.triggerButton,
      GestureTriggerButton(buttonNumber: 7)
    )
    XCTAssertEqual(reloaded.triggerDuration, 0.35)
  }

  @MainActor
  func testInvalidInputConfigurationFallsBackToSafeValues() {
    let (suiteName, userDefaults) = makeUserDefaults()
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    userDefaults.set(-1, forKey: "general.trigger-button")
    userDefaults.set(100, forKey: "general.trigger-duration")

    let store = AppPreferencesStore(userDefaults: userDefaults)

    XCTAssertEqual(store.triggerButton, .right)
    XCTAssertEqual(
      store.triggerDuration,
      GestureInputConfiguration.maximumTriggerDuration
    )
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

  private func makeUserDefaults() -> (String, UserDefaults) {
    let suiteName = "iGesturesTests.\(UUID().uuidString)"
    return (
      suiteName,
      UserDefaults(suiteName: suiteName)!
    )
  }
}
