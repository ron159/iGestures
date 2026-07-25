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

    let reloaded = AppPreferencesStore(userDefaults: userDefaults)
    XCTAssertFalse(reloaded.recognitionEnabled)
    XCTAssertFalse(reloaded.overlayEnabled)
  }

  private func makeUserDefaults() -> (String, UserDefaults) {
    let suiteName = "iGesturesTests.\(UUID().uuidString)"
    return (
      suiteName,
      UserDefaults(suiteName: suiteName)!
    )
  }
}
