import Foundation

@MainActor
public final class AppPreferencesStore {
  private enum Key {
    static let recognitionEnabled =
      "general.recognition-enabled"
    static let overlayEnabled = "general.overlay-enabled"
    static let triggerButton = "general.trigger-button"
    static let triggerDuration = "general.trigger-duration"
  }

  private let userDefaults: UserDefaults

  public init(userDefaults: UserDefaults? = nil) {
    self.userDefaults = userDefaults ?? .standard
  }

  public var recognitionEnabled: Bool {
    storedBool(forKey: Key.recognitionEnabled, defaultValue: true)
  }

  public var overlayEnabled: Bool {
    storedBool(forKey: Key.overlayEnabled, defaultValue: true)
  }

  public var triggerButton: GestureTriggerButton {
    guard
      let number = userDefaults.object(forKey: Key.triggerButton)
        as? NSNumber,
      number.int64Value >= 0,
      number.uint64Value <= UInt64(UInt32.max)
    else {
      return .right
    }
    return GestureTriggerButton(
      buttonNumber: UInt32(number.uint64Value)
    )
  }

  public var triggerDuration: TimeInterval {
    guard userDefaults.object(forKey: Key.triggerDuration) != nil else {
      return GestureInputConfiguration.defaultTriggerDuration
    }
    return GestureInputConfiguration(
      triggerDuration: userDefaults.double(
        forKey: Key.triggerDuration
      )
    ).triggerDuration
  }

  public func setRecognitionEnabled(_ isEnabled: Bool) {
    userDefaults.set(isEnabled, forKey: Key.recognitionEnabled)
  }

  public func setOverlayEnabled(_ isEnabled: Bool) {
    userDefaults.set(isEnabled, forKey: Key.overlayEnabled)
  }

  public func setTriggerButton(_ triggerButton: GestureTriggerButton) {
    userDefaults.set(
      triggerButton.buttonNumber,
      forKey: Key.triggerButton
    )
  }

  public func setTriggerDuration(_ duration: TimeInterval) {
    let validatedDuration = GestureInputConfiguration(
      triggerDuration: duration
    ).triggerDuration
    userDefaults.set(
      validatedDuration,
      forKey: Key.triggerDuration
    )
  }

  private func storedBool(
    forKey key: String,
    defaultValue: Bool
  ) -> Bool {
    guard userDefaults.object(forKey: key) != nil else {
      return defaultValue
    }
    return userDefaults.bool(forKey: key)
  }
}
