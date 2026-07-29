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

@MainActor
public final class AppPreferencesStore {
  private enum Key {
    static let recognitionEnabled =
      "general.recognition-enabled"
    static let overlayEnabled = "general.overlay-enabled"
    static let triggerButton = "general.trigger-button"
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
    static let skippedUpdateVersion = "updates.skipped-version"
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
