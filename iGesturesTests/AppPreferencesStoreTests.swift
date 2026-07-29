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

  private func makeUserDefaults() -> (String, UserDefaults) {
    let suiteName = "iGesturesTests.\(UUID().uuidString)"
    return (
      suiteName,
      UserDefaults(suiteName: suiteName)!
    )
  }
}
