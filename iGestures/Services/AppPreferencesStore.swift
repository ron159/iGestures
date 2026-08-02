import CryptoKit
import Foundation
import Security

public struct ApplicationExclusionRule:
  Codable,
  Hashable,
  Identifiable,
  Sendable
{
  public let bundleIdentifier: String
  public let triggerButton: GestureTriggerButton?

  public init(
    bundleIdentifier: String,
    triggerButton: GestureTriggerButton? = nil
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.triggerButton = triggerButton
  }

  public var id: String {
    "\(bundleIdentifier)#\(triggerButton?.buttonNumber.description ?? "all")"
  }
}

public struct GestureTrailColor: Codable, Equatable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double

  public init?(red: Double, green: Double, blue: Double) {
    guard
      Self.isValid(red),
      Self.isValid(green),
      Self.isValid(blue)
    else {
      return nil
    }
    self.red = red
    self.green = green
    self.blue = blue
  }

  private static func isValid(_ component: Double) -> Bool {
    component.isFinite && (0...1).contains(component)
  }
}

public enum InterfaceAppearance:
  String,
  Codable,
  CaseIterable,
  Sendable
{
  case system
  case light
  case dark
}

public enum InterfaceLanguage:
  String,
  Codable,
  CaseIterable,
  Sendable
{
  case system
  case english
  case simplifiedChinese

  fileprivate var appleLanguages: [String]? {
    switch self {
    case .system:
      nil
    case .english:
      ["en"]
    case .simplifiedChinese:
      ["zh-Hans"]
    }
  }
}

public struct AppSettingsSnapshot: Codable, Equatable, Sendable {
  public let recognitionEnabled: Bool
  public let overlayEnabled: Bool
  public let trailColor: GestureTrailColor?
  public let interfaceAppearance: InterfaceAppearance
  public let interfaceLanguage: InterfaceLanguage
  public let triggerButton: GestureTriggerButton
  public let secondaryTriggerButton: GestureTriggerButton?
  public let triggerDuration: TimeInterval
  public let recognitionSensitivity: RecognitionSensitivity
  public let feedbackEnabled: Bool
  public let globalToggleShortcut: KeyboardShortcut
  public let applicationExclusions: Set<ApplicationExclusionRule>
  public let trackpadGestureEnabled: Bool
  public let trackpadModifiers: UInt64
  public let hapticFeedbackEnabled: Bool
  public let diagnosticPersistenceEnabled: Bool
  public let customActionPresets: [ActionPreset]
  public let favoriteActionPresetIDs: Set<String>
  public let recentActionPresetIDs: [String]
  public let launchAtLoginEnabled: Bool?

  public init(
    recognitionEnabled: Bool = true,
    overlayEnabled: Bool = true,
    trailColor: GestureTrailColor? = nil,
    interfaceAppearance: InterfaceAppearance = .system,
    interfaceLanguage: InterfaceLanguage = .system,
    triggerButton: GestureTriggerButton = .right,
    secondaryTriggerButton: GestureTriggerButton? = nil,
    triggerDuration: TimeInterval =
      GestureInputConfiguration.defaultTriggerDuration,
    recognitionSensitivity: RecognitionSensitivity = .standard,
    feedbackEnabled: Bool = true,
    globalToggleShortcut: KeyboardShortcut = KeyboardShortcut(
      keyCode: 5,
      modifiers: 0x10_0000 | 0x8_0000 | 0x4_0000
    ),
    applicationExclusions: Set<ApplicationExclusionRule> = [],
    trackpadGestureEnabled: Bool = false,
    trackpadModifiers: UInt64 = 0x8_0000 | 0x4_0000,
    hapticFeedbackEnabled: Bool = false,
    diagnosticPersistenceEnabled: Bool = false,
    customActionPresets: [ActionPreset] = [],
    favoriteActionPresetIDs: Set<String> = [],
    recentActionPresetIDs: [String] = [],
    launchAtLoginEnabled: Bool? = nil
  ) {
    self.recognitionEnabled = recognitionEnabled
    self.overlayEnabled = overlayEnabled
    self.trailColor = trailColor
    self.interfaceAppearance = interfaceAppearance
    self.interfaceLanguage = interfaceLanguage
    self.triggerButton = triggerButton
    self.secondaryTriggerButton = secondaryTriggerButton
    self.triggerDuration = triggerDuration
    self.recognitionSensitivity = recognitionSensitivity
    self.feedbackEnabled = feedbackEnabled
    self.globalToggleShortcut = globalToggleShortcut
    self.applicationExclusions = applicationExclusions
    self.trackpadGestureEnabled = trackpadGestureEnabled
    self.trackpadModifiers = trackpadModifiers
    self.hapticFeedbackEnabled = hapticFeedbackEnabled
    self.diagnosticPersistenceEnabled = diagnosticPersistenceEnabled
    self.customActionPresets = customActionPresets
    self.favoriteActionPresetIDs = favoriteActionPresetIDs
    self.recentActionPresetIDs = recentActionPresetIDs
    self.launchAtLoginEnabled = launchAtLoginEnabled
  }
}

@MainActor
public final class AppPreferencesStore {
  private enum Key {
    static let recognitionEnabled =
      "general.recognition-enabled"
    static let overlayEnabled = "general.overlay-enabled"
    static let trailColor = "general.trail-color"
    static let interfaceAppearance = "general.interface-appearance"
    static let interfaceLanguage = "general.interface-language"
    static let triggerButton = "general.trigger-button"
    static let secondaryTriggerButton =
      "general.secondary-trigger-button"
    static let triggerDuration = "general.trigger-duration"
    static let onboardingCompleted = "onboarding.completed"
    static let recognitionSensitivity =
      "recognition.sensitivity"
    static let feedbackEnabled = "feedback.enabled"
    static let globalToggleKeyCode = "global-toggle.key-code"
    static let globalToggleModifiers = "global-toggle.modifiers"
    static let applicationExclusions = "application.exclusions"
    static let trackpadGestureEnabled = "trackpad.gesture-enabled"
    static let trackpadModifiers = "trackpad.modifiers"
    static let hapticFeedbackEnabled = "trackpad.haptic-enabled"
    static let diagnosticPersistenceEnabled =
      "diagnostics.persistence-enabled"
    static let diagnosticRecords = "diagnostics.records"
    static let scriptExecutionNoticeAcknowledged =
      "scripts.execution-notice-acknowledged"
    static let skippedUpdateVersion = "updates.skipped-version"
    static let gestureSidebarGroups = "gestures.sidebar-groups"
    static let gestureSidebarApplications =
      "gestures.sidebar-applications"
    static let customActionPresets = "actions.custom-presets"
    static let favoriteActionPresetIDs = "actions.favorite-preset-ids"
    static let recentActionPresetIDs = "actions.recent-preset-ids"
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

  public var trailColor: GestureTrailColor? {
    guard
      let data = userDefaults.data(forKey: Key.trailColor),
      let storedColor = try? JSONDecoder().decode(
        GestureTrailColor.self,
        from: data
      )
    else {
      return nil
    }
    return GestureTrailColor(
      red: storedColor.red,
      green: storedColor.green,
      blue: storedColor.blue
    )
  }

  public var interfaceAppearance: InterfaceAppearance {
    guard
      let rawValue = userDefaults.string(
        forKey: Key.interfaceAppearance
      ),
      let appearance = InterfaceAppearance(rawValue: rawValue)
    else {
      return .system
    }
    return appearance
  }

  public var interfaceLanguage: InterfaceLanguage {
    guard
      let rawValue = userDefaults.string(forKey: Key.interfaceLanguage),
      let language = InterfaceLanguage(rawValue: rawValue)
    else {
      return .system
    }
    return language
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

  public var secondaryTriggerButton: GestureTriggerButton? {
    guard
      let number = userDefaults.object(
        forKey: Key.secondaryTriggerButton
      ) as? NSNumber,
      number.int64Value >= 0,
      number.uint64Value < UInt64(UInt32.max)
    else {
      return nil
    }
    let button = GestureTriggerButton(
      buttonNumber: UInt32(number.uint64Value)
    )
    return button == triggerButton ? nil : button
  }

  public var onboardingCompleted: Bool {
    userDefaults.bool(forKey: Key.onboardingCompleted)
  }

  public var recognitionSensitivity: RecognitionSensitivity {
    guard
      let rawValue = userDefaults.string(
        forKey: Key.recognitionSensitivity
      ),
      let sensitivity = RecognitionSensitivity(rawValue: rawValue)
    else {
      return .standard
    }
    return sensitivity
  }

  public var feedbackEnabled: Bool {
    storedBool(forKey: Key.feedbackEnabled, defaultValue: true)
  }

  public var globalToggleShortcut: KeyboardShortcut {
    guard
      let keyCode = userDefaults.object(
        forKey: Key.globalToggleKeyCode
      ) as? NSNumber,
      let modifiers = userDefaults.object(
        forKey: Key.globalToggleModifiers
      ) as? NSNumber,
      keyCode.uint64Value <= UInt64(UInt16.max)
    else {
      return KeyboardShortcut(
        keyCode: 5,
        modifiers: 0x10_0000 | 0x8_0000 | 0x4_0000
      )
    }
    return KeyboardShortcut(
      keyCode: UInt16(keyCode.uint64Value),
      modifiers: modifiers.uint64Value
    )
  }

  public var applicationExclusions: Set<ApplicationExclusionRule> {
    guard
      let data = userDefaults.data(
        forKey: Key.applicationExclusions
      ),
      let rules = try? JSONDecoder().decode(
        Set<ApplicationExclusionRule>.self,
        from: data
      )
    else {
      return []
    }
    return rules
  }

  public var trackpadGestureEnabled: Bool {
    userDefaults.bool(forKey: Key.trackpadGestureEnabled)
  }

  public var trackpadModifiers: UInt64 {
    guard
      let number = userDefaults.object(
        forKey: Key.trackpadModifiers
      ) as? NSNumber
    else {
      return 0x8_0000 | 0x4_0000
    }
    return ShortcutRecordingSession.normalizedModifiers(
      number.uint64Value
    )
  }

  public var hapticFeedbackEnabled: Bool {
    userDefaults.bool(forKey: Key.hapticFeedbackEnabled)
  }

  public var diagnosticPersistenceEnabled: Bool {
    userDefaults.bool(forKey: Key.diagnosticPersistenceEnabled)
  }

  public var diagnosticRecords: [GestureDiagnosticRecord] {
    guard
      diagnosticPersistenceEnabled,
      let data = userDefaults.data(forKey: Key.diagnosticRecords),
      let records = try? JSONDecoder().decode(
        [GestureDiagnosticRecord].self,
        from: data
      )
    else {
      return []
    }
    return Array(records.suffix(50))
  }

  public var skippedUpdateVersion: String? {
    userDefaults.string(forKey: Key.skippedUpdateVersion)
  }

  public var scriptExecutionNoticeAcknowledged: Bool {
    userDefaults.bool(forKey: Key.scriptExecutionNoticeAcknowledged)
  }

  public var gestureSidebarGroups: [String] {
    userDefaults.stringArray(forKey: Key.gestureSidebarGroups) ?? []
  }

  public var gestureSidebarApplications: [String] {
    userDefaults.stringArray(
      forKey: Key.gestureSidebarApplications
    ) ?? []
  }

  public var customActionPresets: [ActionPreset] {
    guard
      let data = userDefaults.data(forKey: Key.customActionPresets),
      let presets = try? JSONDecoder().decode(
        [ActionPreset].self,
        from: data
      )
    else {
      return []
    }
    let builtInIDs = Set(ActionPresetLibrary.builtIn.map(\.id))
    var seen: Set<String> = []
    return presets.filter {
      $0.isUserDefined
        && $0.isValid
        && !builtInIDs.contains($0.id)
        && seen.insert($0.id).inserted
    }.prefix(100).map { $0 }
  }

  public var favoriteActionPresetIDs: Set<String> {
    Set(
      userDefaults.stringArray(
        forKey: Key.favoriteActionPresetIDs
      ) ?? []
    )
  }

  public var recentActionPresetIDs: [String] {
    Array(
      orderedUniqueStrings(
        userDefaults.stringArray(
          forKey: Key.recentActionPresetIDs
        ) ?? []
      ).prefix(12)
    )
  }

  public func setRecognitionEnabled(_ isEnabled: Bool) {
    userDefaults.set(isEnabled, forKey: Key.recognitionEnabled)
  }

  public func setOverlayEnabled(_ isEnabled: Bool) {
    userDefaults.set(isEnabled, forKey: Key.overlayEnabled)
  }

  public func setTrailColor(_ color: GestureTrailColor?) {
    guard let color else {
      userDefaults.removeObject(forKey: Key.trailColor)
      return
    }
    guard
      let validatedColor = GestureTrailColor(
        red: color.red,
        green: color.green,
        blue: color.blue
      ),
      let data = try? JSONEncoder().encode(validatedColor)
    else {
      return
    }
    userDefaults.set(data, forKey: Key.trailColor)
  }

  public func setInterfaceAppearance(
    _ appearance: InterfaceAppearance
  ) {
    userDefaults.set(
      appearance.rawValue,
      forKey: Key.interfaceAppearance
    )
  }

  public func setInterfaceLanguage(_ language: InterfaceLanguage) {
    userDefaults.set(language.rawValue, forKey: Key.interfaceLanguage)
    if let appleLanguages = language.appleLanguages {
      userDefaults.set(appleLanguages, forKey: "AppleLanguages")
    } else {
      userDefaults.removeObject(forKey: "AppleLanguages")
    }
  }

  public func setTriggerButton(_ triggerButton: GestureTriggerButton) {
    userDefaults.set(
      triggerButton.buttonNumber,
      forKey: Key.triggerButton
    )
  }

  public func setSecondaryTriggerButton(
    _ triggerButton: GestureTriggerButton?
  ) {
    guard let triggerButton else {
      userDefaults.removeObject(
        forKey: Key.secondaryTriggerButton
      )
      return
    }
    guard
      triggerButton != .trackpad,
      triggerButton != self.triggerButton
    else {
      return
    }
    userDefaults.set(
      triggerButton.buttonNumber,
      forKey: Key.secondaryTriggerButton
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

  public func setOnboardingCompleted(_ completed: Bool) {
    userDefaults.set(completed, forKey: Key.onboardingCompleted)
  }

  public func setRecognitionSensitivity(
    _ sensitivity: RecognitionSensitivity
  ) {
    userDefaults.set(
      sensitivity.rawValue,
      forKey: Key.recognitionSensitivity
    )
  }

  public func setFeedbackEnabled(_ enabled: Bool) {
    userDefaults.set(enabled, forKey: Key.feedbackEnabled)
  }

  public func setGlobalToggleShortcut(
    _ shortcut: KeyboardShortcut
  ) {
    userDefaults.set(
      shortcut.keyCode,
      forKey: Key.globalToggleKeyCode
    )
    userDefaults.set(
      shortcut.modifiers,
      forKey: Key.globalToggleModifiers
    )
  }

  public func setApplicationExclusions(
    _ rules: Set<ApplicationExclusionRule>
  ) {
    guard let data = try? JSONEncoder().encode(rules) else {
      return
    }
    userDefaults.set(data, forKey: Key.applicationExclusions)
  }

  public func setTrackpadGestureEnabled(_ enabled: Bool) {
    userDefaults.set(enabled, forKey: Key.trackpadGestureEnabled)
  }

  public func setTrackpadModifiers(_ modifiers: UInt64) {
    userDefaults.set(
      ShortcutRecordingSession.normalizedModifiers(modifiers),
      forKey: Key.trackpadModifiers
    )
  }

  public func setHapticFeedbackEnabled(_ enabled: Bool) {
    userDefaults.set(enabled, forKey: Key.hapticFeedbackEnabled)
  }

  public func setDiagnosticPersistenceEnabled(_ enabled: Bool) {
    userDefaults.set(
      enabled,
      forKey: Key.diagnosticPersistenceEnabled
    )
    if !enabled {
      userDefaults.removeObject(forKey: Key.diagnosticRecords)
    }
  }

  public func setDiagnosticRecords(
    _ records: [GestureDiagnosticRecord]
  ) {
    guard diagnosticPersistenceEnabled else { return }
    let retained = Array(records.suffix(50))
    guard let data = try? JSONEncoder().encode(retained) else {
      return
    }
    userDefaults.set(data, forKey: Key.diagnosticRecords)
  }

  public func setSkippedUpdateVersion(_ version: String?) {
    userDefaults.set(version, forKey: Key.skippedUpdateVersion)
  }

  public func setScriptExecutionNoticeAcknowledged(
    _ acknowledged: Bool
  ) {
    userDefaults.set(
      acknowledged,
      forKey: Key.scriptExecutionNoticeAcknowledged
    )
  }

  public func setGestureSidebarGroups(_ groups: [String]) {
    userDefaults.set(
      normalizedStrings(groups),
      forKey: Key.gestureSidebarGroups
    )
  }

  public func setGestureSidebarApplications(
    _ bundleIdentifiers: [String]
  ) {
    userDefaults.set(
      normalizedStrings(bundleIdentifiers),
      forKey: Key.gestureSidebarApplications
    )
  }

  public func clearGestureSidebarConfiguration() {
    userDefaults.removeObject(forKey: Key.gestureSidebarGroups)
    userDefaults.removeObject(forKey: Key.gestureSidebarApplications)
  }

  public func setCustomActionPresets(_ presets: [ActionPreset]) {
    let builtInIDs = Set(ActionPresetLibrary.builtIn.map(\.id))
    var seen: Set<String> = []
    let retained = presets.filter {
      $0.isUserDefined
        && $0.isValid
        && !builtInIDs.contains($0.id)
        && seen.insert($0.id).inserted
    }.prefix(100)
    guard let data = try? JSONEncoder().encode(Array(retained)) else {
      return
    }
    userDefaults.set(data, forKey: Key.customActionPresets)
  }

  public func setFavoriteActionPresetIDs(_ identifiers: Set<String>) {
    userDefaults.set(
      identifiers.sorted(),
      forKey: Key.favoriteActionPresetIDs
    )
  }

  public func setRecentActionPresetIDs(_ identifiers: [String]) {
    userDefaults.set(
      Array(orderedUniqueStrings(identifiers).prefix(12)),
      forKey: Key.recentActionPresetIDs
    )
  }

  public func configurationSnapshot(
    launchAtLoginEnabled: Bool? = nil
  ) -> AppSettingsSnapshot {
    AppSettingsSnapshot(
      recognitionEnabled: recognitionEnabled,
      overlayEnabled: overlayEnabled,
      trailColor: trailColor,
      interfaceAppearance: interfaceAppearance,
      interfaceLanguage: interfaceLanguage,
      triggerButton: triggerButton,
      secondaryTriggerButton: secondaryTriggerButton,
      triggerDuration: triggerDuration,
      recognitionSensitivity: recognitionSensitivity,
      feedbackEnabled: feedbackEnabled,
      globalToggleShortcut: globalToggleShortcut,
      applicationExclusions: applicationExclusions,
      trackpadGestureEnabled: trackpadGestureEnabled,
      trackpadModifiers: trackpadModifiers,
      hapticFeedbackEnabled: hapticFeedbackEnabled,
      diagnosticPersistenceEnabled: diagnosticPersistenceEnabled,
      customActionPresets: customActionPresets,
      favoriteActionPresetIDs: favoriteActionPresetIDs,
      recentActionPresetIDs: recentActionPresetIDs,
      launchAtLoginEnabled: launchAtLoginEnabled
    )
  }

  public func applyConfigurationSnapshot(
    _ snapshot: AppSettingsSnapshot
  ) {
    setRecognitionEnabled(snapshot.recognitionEnabled)
    setOverlayEnabled(snapshot.overlayEnabled)
    setTrailColor(snapshot.trailColor)
    setInterfaceAppearance(snapshot.interfaceAppearance)
    setInterfaceLanguage(snapshot.interfaceLanguage)
    setSecondaryTriggerButton(nil)
    setTriggerButton(snapshot.triggerButton)
    setSecondaryTriggerButton(snapshot.secondaryTriggerButton)
    setTriggerDuration(snapshot.triggerDuration)
    setRecognitionSensitivity(snapshot.recognitionSensitivity)
    setFeedbackEnabled(snapshot.feedbackEnabled)
    if snapshot.globalToggleShortcut.isValid {
      setGlobalToggleShortcut(snapshot.globalToggleShortcut)
    }
    setApplicationExclusions(snapshot.applicationExclusions)
    setTrackpadGestureEnabled(snapshot.trackpadGestureEnabled)
    setTrackpadModifiers(snapshot.trackpadModifiers)
    setHapticFeedbackEnabled(snapshot.hapticFeedbackEnabled)
    setDiagnosticPersistenceEnabled(
      snapshot.diagnosticPersistenceEnabled
    )
    setCustomActionPresets(snapshot.customActionPresets)
    setFavoriteActionPresetIDs(snapshot.favoriteActionPresetIDs)
    setRecentActionPresetIDs(snapshot.recentActionPresetIDs)
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

  private func normalizedStrings(_ values: [String]) -> [String] {
    Array(
      Set(
        values.compactMap {
          let value = $0.trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          return value.isEmpty ? nil : value
        }
      )
    ).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  private func orderedUniqueStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.compactMap {
      let value = $0.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !value.isEmpty, seen.insert(value).inserted else {
        return nil
      }
      return value
    }
  }
}

public struct UpdateManifest: Codable, Equatable, Sendable {
  public let version: String
  public let minimumSystemVersion: String
  public let archiveURL: URL
  public let sha256: String
  public let signature: String

  public init(
    version: String,
    minimumSystemVersion: String,
    archiveURL: URL,
    sha256: String,
    signature: String
  ) {
    self.version = version
    self.minimumSystemVersion = minimumSystemVersion
    self.archiveURL = archiveURL
    self.sha256 = sha256
    self.signature = signature
  }

  public var signedPayload: Data {
    Data(
      [
        version,
        minimumSystemVersion,
        archiveURL.absoluteString,
        sha256.lowercased(),
      ].joined(separator: "\n").utf8
    )
  }
}

public struct VerifiedUpdate: Equatable, Sendable {
  public let manifest: UpdateManifest
}

public enum UpdateRejectionReason: Error, Equatable, Sendable {
  case malformedManifest
  case invalidSignature
  case insecureDownload
  case invalidChecksum
  case unsupportedSystem
  case versionRollback
  case networkFailure
}

public enum UpdateCheckResult: Equatable, Sendable {
  case upToDate
  case skipped(version: String)
  case available(VerifiedUpdate)
  case rejected(UpdateRejectionReason)
}

public struct GitHubReleaseDiskImage: Equatable, Sendable {
  public let name: String
  public let downloadURL: URL
  public let checksumURL: URL
  public let byteCount: Int64

  public init(
    name: String,
    downloadURL: URL,
    checksumURL: URL,
    byteCount: Int64
  ) {
    self.name = name
    self.downloadURL = downloadURL
    self.checksumURL = checksumURL
    self.byteCount = byteCount
  }
}

public struct GitHubRelease: Equatable, Sendable {
  public let version: String
  public let pageURL: URL
  public let diskImage: GitHubReleaseDiskImage?

  public init(
    version: String,
    pageURL: URL,
    diskImage: GitHubReleaseDiskImage? = nil
  ) {
    self.version = version
    self.pageURL = pageURL
    self.diskImage = diskImage
  }
}

public enum GitHubReleaseCheckResult: Equatable, Sendable {
  case upToDate
  case skipped(version: String)
  case available(GitHubRelease)
  case rejected(UpdateRejectionReason)
}

public actor GitHubReleaseService {
  private struct AssetResponse: Decodable {
    let name: String
    let downloadURL: URL
    let byteCount: Int64

    enum CodingKeys: String, CodingKey {
      case name
      case downloadURL = "browser_download_url"
      case byteCount = "size"
    }
  }

  private struct ReleaseResponse: Decodable {
    let tagName: String
    let pageURL: URL
    let isDraft: Bool
    let isPrerelease: Bool
    let assets: [AssetResponse]?

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case pageURL = "html_url"
      case isDraft = "draft"
      case isPrerelease = "prerelease"
      case assets
    }
  }

  private let currentVersion: [Int]
  private let latestReleaseURL: URL
  private var skippedVersion: String?

  public init?(
    currentVersion: String,
    latestReleaseURL: URL,
    skippedVersion: String? = nil
  ) {
    guard
      latestReleaseURL.scheme?.lowercased() == "https",
      latestReleaseURL.host?.lowercased() == "api.github.com",
      let version = Self.versionComponents(currentVersion)
    else {
      return nil
    }
    self.currentVersion = version
    self.latestReleaseURL = latestReleaseURL
    self.skippedVersion = skippedVersion
  }

  public func check() async -> GitHubReleaseCheckResult {
    var request = URLRequest(url: latestReleaseURL)
    request.setValue(
      "application/vnd.github+json",
      forHTTPHeaderField: "Accept"
    )
    request.setValue(
      "2022-11-28",
      forHTTPHeaderField: "X-GitHub-Api-Version"
    )
    do {
      let (data, response) = try await URLSession.shared.data(
        for: request
      )
      guard
        let response = response as? HTTPURLResponse,
        (200..<300).contains(response.statusCode)
      else {
        return .rejected(.networkFailure)
      }
      return validate(releaseData: data)
    } catch {
      return .rejected(.networkFailure)
    }
  }

  public func validate(
    releaseData: Data
  ) -> GitHubReleaseCheckResult {
    guard
      let response = try? JSONDecoder().decode(
        ReleaseResponse.self,
        from: releaseData
      ),
      !response.isDraft,
      !response.isPrerelease,
      response.pageURL.scheme?.lowercased() == "https",
      response.pageURL.host?.lowercased() == "github.com"
    else {
      return .rejected(.malformedManifest)
    }
    let version =
      response.tagName.first == "v"
      ? String(response.tagName.dropFirst())
      : response.tagName
    guard let releaseVersion = Self.versionComponents(version) else {
      return .rejected(.malformedManifest)
    }
    let versionComparison = Self.compare(
      releaseVersion,
      currentVersion
    )
    guard versionComparison != .orderedAscending else {
      return .rejected(.versionRollback)
    }
    guard versionComparison == .orderedDescending else {
      return .upToDate
    }
    if skippedVersion == version {
      return .skipped(version: version)
    }
    let archiveName = "iGestures-\(version)-macOS-arm64.dmg"
    let checksumName = "\(archiveName).sha256"
    let assets = response.assets ?? []
    let archive = assets.first { $0.name == archiveName }
    let checksum = assets.first { $0.name == checksumName }
    let diskImage: GitHubReleaseDiskImage?
    if let archive,
      let checksum,
      archive.byteCount > 0,
      Self.isTrustedReleaseAsset(
        archive.downloadURL,
        tagName: response.tagName,
        assetName: archiveName
      ),
      Self.isTrustedReleaseAsset(
        checksum.downloadURL,
        tagName: response.tagName,
        assetName: checksumName
      )
    {
      diskImage = GitHubReleaseDiskImage(
        name: archiveName,
        downloadURL: archive.downloadURL,
        checksumURL: checksum.downloadURL,
        byteCount: archive.byteCount
      )
    } else {
      diskImage = nil
    }
    return .available(
      GitHubRelease(
        version: version,
        pageURL: response.pageURL,
        diskImage: diskImage
      )
    )
  }

  public func skip(version: String) {
    skippedVersion = version
  }

  public func download(
    _ release: GitHubRelease,
    directoryURL: URL
  ) async -> Result<URL, UpdateRejectionReason> {
    guard let diskImage = release.diskImage else {
      return .failure(.malformedManifest)
    }
    do {
      let (checksumData, checksumResponse) =
        try await URLSession.shared.data(from: diskImage.checksumURL)
      guard
        let checksumResponse = checksumResponse as? HTTPURLResponse,
        (200..<300).contains(checksumResponse.statusCode),
        checksumData.count <= 4_096,
        let expectedChecksum = Self.checksum(
          in: checksumData,
          archiveName: diskImage.name
        )
      else {
        return .failure(.invalidChecksum)
      }

      let (temporaryURL, downloadResponse) =
        try await URLSession.shared.download(from: diskImage.downloadURL)
      guard
        let downloadResponse = downloadResponse as? HTTPURLResponse,
        (200..<300).contains(downloadResponse.statusCode)
      else {
        return .failure(.networkFailure)
      }
      let resourceValues = try temporaryURL.resourceValues(
        forKeys: [.fileSizeKey]
      )
      guard
        resourceValues.fileSize.map(Int64.init) == diskImage.byteCount,
        try Self.sha256(of: temporaryURL) == expectedChecksum
      else {
        return .failure(.invalidChecksum)
      }

      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
      )
      let destinationURL = directoryURL.appendingPathComponent(
        diskImage.name
      )
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.moveItem(
        at: temporaryURL,
        to: destinationURL
      )
      return .success(destinationURL)
    } catch {
      return .failure(.networkFailure)
    }
  }

  static func checksum(
    in data: Data,
    archiveName: String
  ) -> String? {
    guard let contents = String(data: data, encoding: .utf8) else {
      return nil
    }
    let matches = contents.split(whereSeparator: \Character.isNewline)
      .compactMap { line -> String? in
        let fields = line.split(
          whereSeparator: \Character.isWhitespace
        )
        guard fields.count == 2 else { return nil }
        let checksum = String(fields[0]).lowercased()
        let name = String(fields[1]).trimmingCharacters(
          in: CharacterSet(charactersIn: "*")
        )
        guard
          name == archiveName,
          checksum.count == 64,
          checksum.allSatisfy(\.isHexDigit)
        else {
          return nil
        }
        return checksum
      }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private static func isTrustedReleaseAsset(
    _ url: URL,
    tagName: String,
    assetName: String
  ) -> Bool {
    guard
      url.scheme?.lowercased() == "https",
      url.host?.lowercased() == "github.com",
      url.query == nil,
      url.fragment == nil
    else {
      return false
    }
    return url.path
      == "/ron159/iGestures/releases/download/\(tagName)/\(assetName)"
  }

  private static func sha256(of fileURL: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: fileURL)
    defer { try? file.close() }
    var hasher = SHA256()
    while let data = try file.read(upToCount: 1_048_576),
      !data.isEmpty
    {
      hasher.update(data: data)
    }
    return hasher.finalize()
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func versionComponents(
    _ value: String
  ) -> [Int]? {
    let parts = value.split(
      separator: ".",
      omittingEmptySubsequences: false
    )
    guard
      (2...4).contains(parts.count),
      parts.allSatisfy({
        !$0.isEmpty
          && $0.allSatisfy(\.isNumber)
          && Int($0) != nil
      })
    else {
      return nil
    }
    return parts.map { Int($0)! }
  }

  private static func compare(
    _ left: [Int],
    _ right: [Int]
  ) -> ComparisonResult {
    let count = max(left.count, right.count)
    for index in 0..<count {
      let leftValue = index < left.count ? left[index] : 0
      let rightValue = index < right.count ? right[index] : 0
      if leftValue < rightValue {
        return .orderedAscending
      }
      if leftValue > rightValue {
        return .orderedDescending
      }
    }
    return .orderedSame
  }
}

public actor UpdateService {
  private let currentVersion: [Int]
  private let publicKey: Curve25519.Signing.PublicKey
  private var skippedVersion: String?

  public init?(
    currentVersion: String,
    publicKeyBase64: String,
    skippedVersion: String? = nil
  ) {
    guard
      let keyData = Data(base64Encoded: publicKeyBase64),
      let publicKey = try? Curve25519.Signing.PublicKey(
        rawRepresentation: keyData
      ),
      let version = Self.versionComponents(currentVersion)
    else {
      return nil
    }
    self.currentVersion = version
    self.publicKey = publicKey
    self.skippedVersion = skippedVersion
  }

  public func check(manifestURL: URL) async -> UpdateCheckResult {
    guard manifestURL.scheme?.lowercased() == "https" else {
      return .rejected(.insecureDownload)
    }
    do {
      let (data, response) = try await URLSession.shared.data(
        from: manifestURL
      )
      guard
        let response = response as? HTTPURLResponse,
        (200..<300).contains(response.statusCode)
      else {
        return .rejected(.networkFailure)
      }
      return validate(manifestData: data)
    } catch {
      return .rejected(.networkFailure)
    }
  }

  public func validate(manifestData: Data) -> UpdateCheckResult {
    guard
      let manifest = try? JSONDecoder().decode(
        UpdateManifest.self,
        from: manifestData
      ),
      manifest.archiveURL.scheme?.lowercased() == "https",
      manifest.sha256.count == 64,
      manifest.sha256.allSatisfy(\.isHexDigit),
      let signature = Data(base64Encoded: manifest.signature),
      let manifestVersion = Self.versionComponents(manifest.version),
      let minimumSystemVersion = Self.versionComponents(
        manifest.minimumSystemVersion
      ),
      let systemVersion = Self.versionComponents(
        operatingSystemVersion
      )
    else {
      return .rejected(.malformedManifest)
    }
    guard
      publicKey.isValidSignature(
        signature,
        for: manifest.signedPayload
      )
    else {
      return .rejected(.invalidSignature)
    }
    guard
      Self.compare(
        minimumSystemVersion,
        systemVersion
      ) != .orderedDescending
    else {
      return .rejected(.unsupportedSystem)
    }
    let versionComparison = Self.compare(
      manifestVersion,
      currentVersion
    )
    guard versionComparison != .orderedAscending else {
      return .rejected(.versionRollback)
    }
    guard versionComparison == .orderedDescending else {
      return .upToDate
    }
    if skippedVersion == manifest.version {
      return .skipped(version: manifest.version)
    }
    return .available(VerifiedUpdate(manifest: manifest))
  }

  public func skip(version: String) {
    skippedVersion = version
  }

  public func download(
    _ update: VerifiedUpdate,
    directoryURL: URL
  ) async -> Result<URL, UpdateRejectionReason> {
    do {
      let (data, response) = try await URLSession.shared.data(
        from: update.manifest.archiveURL
      )
      guard
        let response = response as? HTTPURLResponse,
        (200..<300).contains(response.statusCode)
      else {
        return .failure(.networkFailure)
      }
      let checksum = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
      guard checksum == update.manifest.sha256.lowercased() else {
        return .failure(.invalidChecksum)
      }
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
      )
      let destination = directoryURL.appendingPathComponent(
        "iGestures-\(update.manifest.version).zip"
      )
      try data.write(to: destination, options: .atomic)
      return .success(destination)
    } catch {
      return .failure(.networkFailure)
    }
  }

  private var operatingSystemVersion: String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
  }

  private static func versionComponents(
    _ value: String
  ) -> [Int]? {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard
      (2...4).contains(parts.count),
      parts.allSatisfy({
        !$0.isEmpty
          && $0.allSatisfy(\.isNumber)
          && Int($0) != nil
      })
    else {
      return nil
    }
    return parts.map { Int($0)! }
  }

  private static func compare(
    _ left: [Int],
    _ right: [Int]
  ) -> ComparisonResult {
    let count = max(left.count, right.count)
    for index in 0..<count {
      let leftValue = index < left.count ? left[index] : 0
      let rightValue = index < right.count ? right[index] : 0
      if leftValue < rightValue {
        return .orderedAscending
      }
      if leftValue > rightValue {
        return .orderedDescending
      }
    }
    return .orderedSame
  }
}

public enum UpdateInstallationError: Error, Equatable, Sendable {
  case invalidArchive
  case invalidBundle
  case invalidSignature
  case identityMismatch
  case versionMismatch
  case replacementFailed
}

public actor UpdatePackageInstaller {
  public init() {}

  public func stage(
    archiveURL: URL,
    in directoryURL: URL
  ) async throws -> URL {
    let stagingURL = directoryURL.appendingPathComponent(
      "staged-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: stagingURL,
      withIntermediateDirectories: true
    )
    let status = await runProcess(
      executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
      arguments: [
        "-x",
        "-k",
        archiveURL.path,
        stagingURL.path,
      ]
    )
    guard status == 0 else {
      throw UpdateInstallationError.invalidArchive
    }
    guard
      let enumerator = FileManager.default.enumerator(
        at: stagingURL,
        includingPropertiesForKeys: [.isDirectoryKey]
      ),
      let applicationURL = enumerator.compactMap({
        $0 as? URL
      }).first(where: {
        $0.pathExtension == "app"
          && $0.lastPathComponent == "iGestures.app"
      })
    else {
      throw UpdateInstallationError.invalidArchive
    }
    return applicationURL
  }

  public func install(
    stagedApplicationURL: URL,
    currentApplicationURL: URL,
    expectedVersion: String,
    expectedBundleIdentifier: String
  ) throws -> URL {
    guard
      let stagedBundle = Bundle(url: stagedApplicationURL),
      stagedBundle.bundleIdentifier == expectedBundleIdentifier
    else {
      throw UpdateInstallationError.invalidBundle
    }
    guard
      stagedBundle.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String == expectedVersion
    else {
      throw UpdateInstallationError.versionMismatch
    }
    let stagedCode = try staticCode(at: stagedApplicationURL)
    let currentCode = try staticCode(at: currentApplicationURL)
    let strictFlags = SecCSFlags(
      rawValue: UInt32(kSecCSStrictValidate | kSecCSCheckAllArchitectures)
    )
    guard
      SecStaticCodeCheckValidity(
        stagedCode,
        strictFlags,
        nil
      ) == errSecSuccess
    else {
      throw UpdateInstallationError.invalidSignature
    }
    var requirement: SecRequirement?
    guard
      SecCodeCopyDesignatedRequirement(
        currentCode,
        [],
        &requirement
      ) == errSecSuccess,
      let requirement,
      SecStaticCodeCheckValidity(
        stagedCode,
        strictFlags,
        requirement
      ) == errSecSuccess
    else {
      throw UpdateInstallationError.identityMismatch
    }

    do {
      _ = try FileManager.default.replaceItemAt(
        currentApplicationURL,
        withItemAt: stagedApplicationURL,
        backupItemName: "iGestures.previous.app",
        options: []
      )
      return currentApplicationURL
    } catch {
      throw UpdateInstallationError.replacementFailed
    }
  }

  private func staticCode(at url: URL) throws -> SecStaticCode {
    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        == errSecSuccess,
      let code
    else {
      throw UpdateInstallationError.invalidSignature
    }
    return code
  }

  private func runProcess(
    executableURL: URL,
    arguments: [String]
  ) async -> Int32 {
    await withCheckedContinuation { continuation in
      do {
        try Process.run(
          executableURL,
          arguments: arguments
        ) {
          continuation.resume(
            returning: $0.terminationStatus
          )
        }
      } catch {
        continuation.resume(returning: -1)
      }
    }
  }
}
