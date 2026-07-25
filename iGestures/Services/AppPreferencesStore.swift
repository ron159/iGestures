import Foundation

@MainActor
public final class AppPreferencesStore {
  private enum Key {
    static let recognitionEnabled =
      "general.recognition-enabled"
    static let overlayEnabled = "general.overlay-enabled"
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

  public func setRecognitionEnabled(_ isEnabled: Bool) {
    userDefaults.set(isEnabled, forKey: Key.recognitionEnabled)
  }

  public func setOverlayEnabled(_ isEnabled: Bool) {
    userDefaults.set(isEnabled, forKey: Key.overlayEnabled)
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
