import AppKit
import Foundation

enum AppUpdateState: Equatable {
  case unavailable
  case idle
  case checking
  case upToDate
  case skipped(version: String)
  case available(version: String)
  case downloading(version: String)
  case installing(version: String)
  case failed
}

@MainActor
private final class ScriptExecutionNoticeAuthorizer {
  private let preferencesStore: AppPreferencesStore

  init(preferencesStore: AppPreferencesStore) {
    self.preferencesStore = preferencesStore
  }

  func authorize(_ script: AutomationScript) -> Bool {
    guard !preferencesStore.scriptExecutionNoticeAcknowledged else {
      return true
    }

    NSApp.activate()
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = String(
      localized: "Run Automation Scripts?"
    )
    alert.informativeText = String(
      localized:
        "Shell scripts run directly with /bin/zsh; Terminal does not open. AppleScript runs with /usr/bin/osascript and macOS may ask for Automation access to each app it controls. Scripts can modify files and system settings, so only continue with scripts you trust."
    )
    alert.addButton(withTitle: String(localized: "Continue"))
    alert.addButton(withTitle: String(localized: "Cancel"))

    guard alert.runModal() == .alertFirstButtonReturn else {
      return false
    }
    preferencesStore.setScriptExecutionNoticeAcknowledged(true)
    return true
  }
}

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published private(set) var isOverlayEnabled = true
  @Published private(set) var trailColor = NSColor.controlAccentColor
  @Published private(set) var triggerButton: GestureTriggerButton = .right
  @Published private(set) var secondaryTriggerButton: GestureTriggerButton?
  @Published private(set) var triggerConfigurationError: String?
  @Published private(set) var triggerDuration =
    GestureInputConfiguration.defaultTriggerDuration
  @Published private(set) var recognitionSensitivity: RecognitionSensitivity = .standard
  @Published private(set) var isFeedbackEnabled = true
  @Published private(set) var globalToggleShortcut =
    KeyboardShortcut(
      keyCode: 5,
      modifiers: 0x10_0000 | 0x8_0000 | 0x4_0000
    )
  @Published private(set) var isTrackpadGestureEnabled = false
  @Published private(set) var trackpadModifiers: UInt64 =
    0x8_0000 | 0x4_0000
  @Published private(set) var isHapticFeedbackEnabled = false
  @Published private(set) var isDiagnosticPersistenceEnabled = false
  @Published private(set) var recentDiagnostics: [GestureDiagnosticRecord] = []
  @Published private(set) var permissionState: PermissionState = .unknown
  @Published private(set) var eventTapState: EventTapManagerState = .stopped
  @Published private(set) var mappingCount = 0
  @Published private(set) var mappings: [GestureMapping] = []
  @Published private(set) var mappingStoreError: String?
  @Published private(set) var isLoadingMappings = true
  @Published private(set) var userScriptLibrary: [ScriptLibraryItem] = []
  @Published private(set) var scriptLibraryError: String?
  @Published private(set) var isLoadingScriptLibrary = true
  @Published private(set) var customActionPresets: [ActionPreset] = []
  @Published private(set) var favoriteActionPresetIDs: Set<String> = []
  @Published private(set) var recentActionPresetIDs: [String] = []
  @Published private(set) var loginItemState: LoginItemState
  @Published private(set) var loginItemError: String?
  @Published private(set) var isTransferringMappings = false
  @Published private(set) var mappingTransferMessage: String?
  @Published private(set) var pendingImportPreview: MappingImportPreview?
  @Published private(set) var canUndoLastImport = false
  @Published private(set) var applicationExclusions: Set<ApplicationExclusionRule> = []
  @Published private(set) var gestureApplicationGroups: [GestureApplicationGroup] = []
  @Published private(set) var managedApplicationBundleIdentifiers: [String] = []
  @Published private(set) var currentApplicationName: String?
  @Published private(set) var currentApplicationBundleIdentifier: String?
  @Published private(set) var updateState: AppUpdateState = .unavailable
  @Published private(set) var updateMessage: String?
  @Published var isOnboardingPresented: Bool

  private let permissionCoordinator: PermissionCoordinator
  private let preferencesStore: AppPreferencesStore
  private let loginItemController: LoginItemController
  private let eventTapManager: EventTapManager
  private let mappingStore: MappingStore?
  private let scriptLibraryStore: ScriptLibraryStore?
  private let overlayController: OverlayController
  private let diagnosticsBuffer: GestureDiagnosticsBuffer
  private let updateService: UpdateService?
  private let githubReleaseService: GitHubReleaseService?
  private let updateInstaller: UpdatePackageInstaller
  private let updateManifestURL: URL?
  private var availableUpdate: VerifiedUpdate?
  private var availableGitHubRelease: GitHubRelease?
  private var database = GestureDatabase.empty
  private var persistenceTask: Task<Void, Never>?
  private var scriptLibraryPersistenceTask: Task<Void, Never>?
  private var applicationActivationTask: Task<Void, Never>?
  private var applicationLifecycleTask: Task<Void, Never>?
  private var pendingImportURL: URL?

  init(
    permissionCoordinator: PermissionCoordinator? = nil,
    preferencesStore: AppPreferencesStore? = nil,
    loginItemController: LoginItemController? = nil,
    eventTapManager: EventTapManager? = nil,
    mappingStore: MappingStore? = nil,
    scriptLibraryStore: ScriptLibraryStore? = nil
  ) {
    let overlayController = OverlayController()
    self.permissionCoordinator =
      permissionCoordinator ?? PermissionCoordinator()
    let preferencesStore =
      preferencesStore ?? AppPreferencesStore()
    self.preferencesStore = preferencesStore
    let scriptExecutionAuthorizer =
      ScriptExecutionNoticeAuthorizer(
        preferencesStore: preferencesStore
      )
    self.isEnabled = preferencesStore.recognitionEnabled
    self.isOverlayEnabled = preferencesStore.overlayEnabled
    self.trailColor =
      preferencesStore.trailColor?.nsColor
      ?? .controlAccentColor
    self.triggerButton = preferencesStore.triggerButton
    self.secondaryTriggerButton =
      preferencesStore.secondaryTriggerButton
    self.triggerDuration = preferencesStore.triggerDuration
    self.recognitionSensitivity =
      preferencesStore.recognitionSensitivity
    self.isFeedbackEnabled = preferencesStore.feedbackEnabled
    self.globalToggleShortcut =
      preferencesStore.globalToggleShortcut
    self.applicationExclusions =
      preferencesStore.applicationExclusions
    self.isTrackpadGestureEnabled =
      preferencesStore.trackpadGestureEnabled
    self.trackpadModifiers = preferencesStore.trackpadModifiers
    self.isHapticFeedbackEnabled =
      preferencesStore.hapticFeedbackEnabled
    self.isDiagnosticPersistenceEnabled =
      preferencesStore.diagnosticPersistenceEnabled
    let diagnosticsBuffer = GestureDiagnosticsBuffer(
      initialRecords: preferencesStore.diagnosticRecords
    )
    self.diagnosticsBuffer = diagnosticsBuffer
    self.recentDiagnostics = preferencesStore.diagnosticRecords
    self.customActionPresets = preferencesStore.customActionPresets
    self.favoriteActionPresetIDs =
      preferencesStore.favoriteActionPresetIDs
    self.recentActionPresetIDs =
      preferencesStore.recentActionPresetIDs
    let manifestURL =
      (Bundle.main.object(
        forInfoDictionaryKey: "IGesturesUpdateManifestURL"
      ) as? String).flatMap(URL.init(string:))
    let publicKey =
      Bundle.main.object(
        forInfoDictionaryKey: "IGesturesUpdatePublicKey"
      ) as? String
    let currentVersion =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "0.0"
    let updateService = publicKey.flatMap {
      UpdateService(
        currentVersion: currentVersion,
        publicKeyBase64: $0,
        skippedVersion: preferencesStore.skippedUpdateVersion
      )
    }
    let githubLatestReleaseURL = URL(
      string:
        "https://api.github.com/repos/ron159/iGestures/releases/latest"
    )
    let githubReleaseService = githubLatestReleaseURL.flatMap {
      GitHubReleaseService(
        currentVersion: currentVersion,
        latestReleaseURL: $0,
        skippedVersion: preferencesStore.skippedUpdateVersion
      )
    }
    self.updateManifestURL = manifestURL
    self.updateService = updateService
    self.githubReleaseService = githubReleaseService
    self.updateInstaller = UpdatePackageInstaller()
    let hasSignedUpdateFeed =
      updateService != nil && manifestURL != nil
    self.updateState =
      hasSignedUpdateFeed || githubReleaseService != nil
      ? .idle
      : .unavailable
    self.isOnboardingPresented =
      !preferencesStore.onboardingCompleted
    let loginItemController =
      loginItemController ?? LoginItemController()
    self.loginItemController = loginItemController
    self.loginItemState = loginItemController.state
    self.overlayController = overlayController
    self.eventTapManager =
      eventTapManager
      ?? EventTapManager(
        actionExecutor: SystemGestureActionExecutor(
          scriptExecutionAuthorizer: { script in
            scriptExecutionAuthorizer.authorize(script)
          }
        ),
        overlaySink: overlayController.eventSink,
        feedbackSink: CompositeGestureFeedbackSink([
          overlayController.feedbackSink,
          diagnosticsBuffer,
        ])
      )
    self.mappingStore =
      mappingStore
      ?? (try? MappingStore.live(
        bundleIdentifier: Bundle.main.bundleIdentifier
          ?? "com.ron159.igestures.dev"
      ))
    self.scriptLibraryStore =
      scriptLibraryStore
      ?? (try? ScriptLibraryStore.live(
        bundleIdentifier: Bundle.main.bundleIdentifier
          ?? "com.ron159.igestures.dev"
      ))
    overlayController.eventSink.setEnabled(isOverlayEnabled)
    overlayController.setTrailColor(trailColor)
    overlayController.feedbackSink.setEnabled(isFeedbackEnabled)
    overlayController.setHapticFeedbackEnabled(
      isHapticFeedbackEnabled
    )
    self.eventTapManager.updateInputConfiguration(
      gestureInputConfiguration
    )
    self.eventTapManager.updateRecognitionSensitivity(
      recognitionSensitivity
    )
    self.eventTapManager.configureGlobalToggle(
      shortcut: globalToggleShortcut
    ) { [weak self] in
      Task { @MainActor [weak self] in
        self?.toggleEnabled()
      }
    }
    self.eventTapManager.updateApplicationExclusions(
      applicationExclusions
    )
    refreshFrontmostApplication()
    self.eventTapManager.setStateHandler { [weak self] state in
      Task { @MainActor [weak self] in
        self?.handleEventTapState(state)
      }
    }
    diagnosticsBuffer.setHandler { [weak self] records in
      Task { @MainActor [weak self] in
        guard let self else { return }
        recentDiagnostics = records
        preferencesStore.setDiagnosticRecords(records)
      }
    }
    observeApplicationActivation()
    observeApplicationLifecycle()
    refreshPermissions()
    reloadMappings()
    reloadScriptLibrary()
    if hasSignedUpdateFeed || githubReleaseService != nil {
      checkForUpdates()
    }
  }

  deinit {
    applicationActivationTask?.cancel()
    applicationLifecycleTask?.cancel()
    persistenceTask?.cancel()
    scriptLibraryPersistenceTask?.cancel()
  }

  var permissionStatusText: String {
    switch permissionState {
    case .unknown:
      String(localized: "Permission: Not checked")
    case .needsUserAction:
      String(localized: "Permission: Action required")
    case .checking:
      String(localized: "Permission: Checking")
    case .granted:
      String(localized: "Permission: Granted")
    case .denied:
      String(localized: "Permission: Denied")
    case .tapCreationFailed:
      String(localized: "Permission: Event Tap unavailable")
    }
  }

  var canRequestAccess: Bool {
    switch permissionState {
    case .needsUserAction, .denied, .tapCreationFailed:
      true
    case .unknown, .checking, .granted:
      false
    }
  }

  var permissionDiagnostics: PermissionDiagnostics {
    permissionCoordinator.diagnostics
  }

  var canInstallAvailableUpdate: Bool {
    availableUpdate != nil
  }

  var canOpenAvailableGitHubRelease: Bool {
    availableGitHubRelease != nil
  }

  var isLaunchAtLoginEnabled: Bool {
    loginItemState == .enabled
  }

  var canChangeLaunchAtLogin: Bool {
    switch loginItemState {
    case .notRegistered, .enabled:
      true
    case .requiresApproval, .notFound:
      false
    }
  }

  func refreshPermissions() {
    permissionState = permissionCoordinator.refresh()
    if permissionState == .checking,
      eventTapState == .running
    {
      permissionState = permissionCoordinator.recordEventTapCreation(
        succeeded: true
      )
    }
    if permissionState == .checking || permissionState == .granted {
      eventTapManager.start()
      eventTapManager.setEnabled(isEnabled)
    } else {
      eventTapManager.stop(reason: .permissionLost)
    }
  }

  func requestAccess() {
    permissionState = permissionCoordinator.requestAccess()
  }

  func requestAccessibilityAccess() {
    permissionState =
      permissionCoordinator.requestAccessibilityAccess()
  }

  func requestListenEventAccess() {
    permissionState =
      permissionCoordinator.requestListenEventAccess()
  }

  func requestPostEventAccess() {
    permissionState =
      permissionCoordinator.requestPostEventAccess()
  }

  func refreshLoginItemStatus() {
    loginItemState = loginItemController.refresh()
  }

  func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
    do {
      loginItemState = try loginItemController.setEnabled(isEnabled)
      loginItemError = nil
    } catch {
      refreshLoginItemStatus()
      loginItemError = String(
        localized: "Launch at login could not be changed."
      )
    }
  }

  func openLoginItemSettings() {
    loginItemController.openSystemSettings()
  }

  func toggleEnabled() {
    isEnabled.toggle()
    preferencesStore.setRecognitionEnabled(isEnabled)
    eventTapManager.setEnabled(isEnabled)
    if isEnabled,
      permissionState == .checking || permissionState == .granted
    {
      eventTapManager.start()
    }
  }

  func setOverlayEnabled(_ isEnabled: Bool) {
    isOverlayEnabled = isEnabled
    preferencesStore.setOverlayEnabled(isEnabled)
    overlayController.eventSink.setEnabled(isEnabled)
  }

  func setTrailColor(_ color: NSColor) {
    guard
      let color = color.usingColorSpace(.sRGB),
      let storedColor = GestureTrailColor(
        red: color.redComponent,
        green: color.greenComponent,
        blue: color.blueComponent
      )
    else {
      return
    }
    trailColor = color
    preferencesStore.setTrailColor(storedColor)
    overlayController.setTrailColor(color)
  }

  func setFeedbackEnabled(_ isEnabled: Bool) {
    isFeedbackEnabled = isEnabled
    preferencesStore.setFeedbackEnabled(isEnabled)
    overlayController.feedbackSink.setEnabled(isEnabled)
  }

  func setRecognitionSensitivity(
    _ sensitivity: RecognitionSensitivity
  ) {
    recognitionSensitivity = sensitivity
    preferencesStore.setRecognitionSensitivity(sensitivity)
    eventTapManager.updateRecognitionSensitivity(sensitivity)
  }

  func setGlobalToggleShortcut(_ shortcut: KeyboardShortcut) {
    let normalized = KeyboardShortcut(
      keyCode: shortcut.keyCode,
      modifiers: ShortcutRecordingSession.normalizedModifiers(
        shortcut.modifiers
      )
    )
    guard normalized.isValid else { return }
    globalToggleShortcut = normalized
    preferencesStore.setGlobalToggleShortcut(normalized)
    eventTapManager.configureGlobalToggle(
      shortcut: normalized
    ) { [weak self] in
      Task { @MainActor [weak self] in
        self?.toggleEnabled()
      }
    }
  }

  func setTrackpadGestureEnabled(_ enabled: Bool) {
    isTrackpadGestureEnabled = enabled
    preferencesStore.setTrackpadGestureEnabled(enabled)
    eventTapManager.updateInputConfiguration(
      gestureInputConfiguration
    )
  }

  func setTrackpadModifiers(_ modifiers: UInt64) {
    trackpadModifiers =
      ShortcutRecordingSession.normalizedModifiers(modifiers)
    preferencesStore.setTrackpadModifiers(trackpadModifiers)
    eventTapManager.updateInputConfiguration(
      gestureInputConfiguration
    )
  }

  func setHapticFeedbackEnabled(_ enabled: Bool) {
    isHapticFeedbackEnabled = enabled
    preferencesStore.setHapticFeedbackEnabled(enabled)
    overlayController.setHapticFeedbackEnabled(enabled)
  }

  func setDiagnosticPersistenceEnabled(_ enabled: Bool) {
    isDiagnosticPersistenceEnabled = enabled
    preferencesStore.setDiagnosticPersistenceEnabled(enabled)
    if enabled {
      preferencesStore.setDiagnosticRecords(recentDiagnostics)
    }
  }

  func clearDiagnostics() {
    diagnosticsBuffer.clear()
  }

  func checkForUpdates(manual: Bool = false) {
    let canCheckSignedFeed =
      updateService != nil && updateManifestURL != nil
    guard canCheckSignedFeed || githubReleaseService != nil else {
      if manual {
        updateState = .unavailable
        updateMessage = String(
          localized:
            "Updates are published on GitHub Releases."
        )
      }
      return
    }
    updateState = .checking
    updateMessage = nil
    Task { @MainActor [weak self] in
      guard let self else { return }
      if let updateService, let updateManifestURL {
        let result = await updateService.check(
          manifestURL: updateManifestURL
        )
        handleUpdateCheckResult(result)
      } else if let githubReleaseService {
        let result = await githubReleaseService.check()
        handleGitHubReleaseCheckResult(result)
      }
    }
  }

  func skipAvailableUpdate() {
    guard
      let version =
        availableUpdate?.manifest.version
        ?? availableGitHubRelease?.version
    else {
      return
    }
    if let updateService {
      Task {
        await updateService.skip(version: version)
      }
    }
    if let githubReleaseService {
      Task {
        await githubReleaseService.skip(version: version)
      }
    }
    preferencesStore.setSkippedUpdateVersion(version)
    self.availableUpdate = nil
    self.availableGitHubRelease = nil
    updateState = .skipped(version: version)
    updateMessage = String(
      format: String(localized: "Version %@ was skipped."),
      version
    )
  }

  func installAvailableUpdate() {
    guard let availableUpdate else { return }
    let version = availableUpdate.manifest.version
    updateState = .downloading(version: version)
    updateMessage = nil
    Task { @MainActor [weak self] in
      guard let self else { return }
      let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "iGestures-update",
          isDirectory: true
        )
      let download = await updateService?.download(
        availableUpdate,
        directoryURL: directoryURL
      )
      guard case .success(let archiveURL) = download else {
        updateState = .failed
        updateMessage = String(
          localized:
            "The update download failed validation. The current version was not changed."
        )
        return
      }
      do {
        updateState = .installing(version: version)
        let stagedURL = try await updateInstaller.stage(
          archiveURL: archiveURL,
          in: directoryURL
        )
        let bundleIdentifier =
          Bundle.main.bundleIdentifier ?? "com.ron159.igestures"
        let installedURL = try await updateInstaller.install(
          stagedApplicationURL: stagedURL,
          currentApplicationURL: Bundle.main.bundleURL,
          expectedVersion: version,
          expectedBundleIdentifier: bundleIdentifier
        )
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
          at: installedURL,
          configuration: configuration
        ) { [weak self] _, error in
          Task { @MainActor [weak self] in
            if error == nil {
              self?.terminate()
            } else {
              self?.updateState = .failed
              self?.updateMessage = String(
                localized:
                  "The update was installed but could not be restarted."
              )
            }
          }
        }
      } catch {
        updateState = .failed
        updateMessage = String(
          localized:
            "The update package was rejected. The current version remains available."
        )
      }
    }
  }

  func openAvailableGitHubRelease() {
    guard let availableGitHubRelease else { return }
    NSWorkspace.shared.open(availableGitHubRelease.pageURL)
  }

  @discardableResult
  func setTriggerButton(
    _ triggerButton: GestureTriggerButton
  ) -> Bool {
    guard triggerButton != secondaryTriggerButton else {
      triggerConfigurationError = String(
        localized:
          "Primary and secondary trigger buttons must be different."
      )
      return false
    }
    self.triggerButton = triggerButton
    triggerConfigurationError = nil
    preferencesStore.setTriggerButton(triggerButton)
    eventTapManager.updateInputConfiguration(
      gestureInputConfiguration
    )
    return true
  }

  @discardableResult
  func setSecondaryTriggerButton(
    _ triggerButton: GestureTriggerButton?
  ) -> Bool {
    guard let triggerButton else {
      secondaryTriggerButton = nil
      triggerConfigurationError = nil
      preferencesStore.setSecondaryTriggerButton(nil)
      eventTapManager.updateInputConfiguration(
        gestureInputConfiguration
      )
      return true
    }
    guard triggerButton != .trackpad else {
      triggerConfigurationError = String(
        localized:
          "Trackpad cannot be used as the secondary mouse trigger."
      )
      return false
    }
    guard triggerButton != self.triggerButton else {
      triggerConfigurationError = String(
        localized:
          "Primary and secondary trigger buttons must be different."
      )
      return false
    }
    guard
      !mappings.contains(where: {
        $0.triggerButton == triggerButton
      })
    else {
      triggerConfigurationError = String(
        localized:
          "The secondary trigger button is already used by a gesture."
      )
      return false
    }
    secondaryTriggerButton = triggerButton
    triggerConfigurationError = nil
    preferencesStore.setSecondaryTriggerButton(triggerButton)
    eventTapManager.updateInputConfiguration(
      gestureInputConfiguration
    )
    return true
  }

  func setTriggerDuration(_ duration: TimeInterval) {
    let configuration = GestureInputConfiguration(
      triggerButton: triggerButton,
      secondaryTriggerButton: secondaryTriggerButton,
      triggerDuration: duration,
      isTrackpadGestureEnabled: isTrackpadGestureEnabled,
      trackpadModifiers: trackpadModifiers
    )
    triggerDuration = configuration.triggerDuration
    preferencesStore.setTriggerDuration(
      configuration.triggerDuration
    )
    eventTapManager.updateInputConfiguration(configuration)
  }

  @discardableResult
  func beginTriggerButtonRecording(
    _ handler:
      @escaping EventTapManager.TriggerButtonRecordingHandler
  ) -> UUID {
    eventTapManager.beginTriggerButtonRecording(handler)
  }

  func endTriggerButtonRecording(id: UUID) {
    eventTapManager.endTriggerButtonRecording(id: id)
  }

  @discardableResult
  func beginShortcutRecording(
    _ handler: @escaping EventTapManager.ShortcutRecordingHandler
  ) -> UUID {
    eventTapManager.beginShortcutRecording(handler)
  }

  func endShortcutRecording(id: UUID) {
    eventTapManager.endShortcutRecording(id: id)
  }

  func terminate() {
    eventTapManager.stop()
    NSApplication.shared.terminate(nil)
  }

  func finishOnboarding() {
    preferencesStore.setOnboardingCompleted(true)
    isOnboardingPresented = false
  }

  func reopenOnboarding() {
    isOnboardingPresented = true
  }

  var isCurrentApplicationExcluded: Bool {
    guard let bundleIdentifier = currentApplicationBundleIdentifier
    else {
      return false
    }
    return applicationExclusions.contains {
      $0.bundleIdentifier == bundleIdentifier
        && $0.triggerButton == nil
    }
  }

  func setCurrentApplicationExcluded(
    _ excluded: Bool,
    triggerButton: GestureTriggerButton? = nil
  ) {
    guard let bundleIdentifier = currentApplicationBundleIdentifier
    else {
      return
    }
    let rule = ApplicationExclusionRule(
      bundleIdentifier: bundleIdentifier,
      triggerButton: triggerButton
    )
    if excluded {
      applicationExclusions.insert(rule)
    } else {
      applicationExclusions.remove(rule)
    }
    preferencesStore.setApplicationExclusions(applicationExclusions)
    eventTapManager.updateApplicationExclusions(applicationExclusions)
  }

  func removeApplicationExclusion(
    _ rule: ApplicationExclusionRule
  ) {
    applicationExclusions.remove(rule)
    preferencesStore.setApplicationExclusions(applicationExclusions)
    eventTapManager.updateApplicationExclusions(applicationExclusions)
  }

  func reloadMappings() {
    isLoadingMappings = true
    guard let mappingStore else {
      isLoadingMappings = false
      mappingStoreError = String(
        localized: "Gesture storage is unavailable."
      )
      eventTapManager.updateMappingSnapshot(.empty)
      return
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let loadedDatabase = try await mappingStore.load()
        let migratedDatabase = migrateLegacySidebarConfiguration(
          in: loadedDatabase
        )
        if migratedDatabase == loadedDatabase {
          install(loadedDatabase)
        } else {
          apply(migratedDatabase)
        }
        canUndoLastImport = await mappingStore.canUndoLastImport()
        isLoadingMappings = false
      } catch {
        database = .empty
        mappings = []
        gestureApplicationGroups = []
        managedApplicationBundleIdentifiers = []
        mappingCount = 0
        isLoadingMappings = false
        mappingStoreError = String(
          localized: "Gesture data could not be loaded."
        )
        eventTapManager.updateMappingSnapshot(.empty)
      }
    }
  }

  @discardableResult
  func createMapping(_ draft: GestureMappingDraft) -> UUID? {
    guard draft.triggerButton != secondaryTriggerButton else {
      triggerConfigurationError = String(
        localized:
          "This button is reserved as the secondary trigger."
      )
      return nil
    }
    var library = GestureLibrary(database: database)
    let id = library.create(draft)
    apply(library.database)
    return id
  }

  func updateMapping(
    id: UUID,
    with draft: GestureMappingDraft
  ) {
    guard draft.triggerButton != secondaryTriggerButton else {
      triggerConfigurationError = String(
        localized:
          "This button is reserved as the secondary trigger."
      )
      return
    }
    mutateLibrary {
      try $0.update(id: id, with: draft)
    }
  }

  func renameMapping(id: UUID, name: String) {
    mutateLibrary {
      try $0.rename(id: id, to: name)
    }
  }

  func setMappingEnabled(id: UUID, isEnabled: Bool) {
    mutateLibrary {
      try $0.setEnabled(id: id, isEnabled)
    }
  }

  func setMappingShortcut(
    id: UUID,
    shortcut: KeyboardShortcut
  ) {
    mutateLibrary {
      try $0.setShortcut(id: id, shortcut)
    }
  }

  func setMappingAction(
    id: UUID,
    action: GestureAction
  ) {
    mutateLibrary {
      try $0.setAction(id: id, action)
    }
  }

  func setMappingSecondaryAction(
    id: UUID,
    action: GestureAction?
  ) {
    mutateLibrary {
      try $0.setSecondaryAction(id: id, action)
    }
  }

  func setMappingAppScope(id: UUID, appScope: AppScope) {
    mutateLibrary {
      try $0.setApplicationGroup(id: id, nil)
      try $0.setAppScope(id: id, appScope)
    }
  }

  func setMappingTriggerButton(
    id: UUID,
    triggerButton: GestureTriggerButton?
  ) {
    guard triggerButton != secondaryTriggerButton else {
      triggerConfigurationError = String(
        localized:
          "This button is reserved as the secondary trigger."
      )
      return
    }
    triggerConfigurationError = nil
    mutateLibrary {
      try $0.setTriggerButton(id: id, triggerButton)
    }
  }

  func setMappingCategory(id: UUID, category: String?) {
    mutateLibrary {
      try $0.setCategory(id: id, category)
    }
  }

  func setMappingRepeatModeEnabled(id: UUID, enabled: Bool) {
    mutateLibrary {
      try $0.setRepeatModeEnabled(id: id, enabled)
    }
  }

  func setMappingDeviceScope(
    id: UUID,
    deviceScope: InputDeviceScope
  ) {
    mutateLibrary {
      try $0.setDeviceScope(id: id, deviceScope)
    }
  }

  @discardableResult
  func addGestureApplicationGroup(_ name: String) -> UUID? {
    let normalized = name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalized.isEmpty else { return nil }
    if let existing = database.applicationGroups.first(where: {
      $0.name.compare(
        normalized,
        options: [.caseInsensitive, .diacriticInsensitive]
      ) == .orderedSame
    }) {
      return existing.id
    }
    var updated = database
    let group = GestureApplicationGroup(name: normalized)
    updated.applicationGroups.append(group)
    apply(updated)
    return group.id
  }

  func deleteGestureApplicationGroup(id: UUID) {
    guard
      let group = database.applicationGroups.first(where: {
        $0.id == id
      })
    else {
      return
    }
    let hasGroupMappings = database.mappings.contains {
      $0.applicationGroupID == id
    }
    guard !group.bundleIdentifiers.isEmpty || !hasGroupMappings else {
      return
    }
    var updated = database
    updated.applicationGroups.removeAll { $0.id == id }
    for index in updated.mappings.indices
    where updated.mappings[index].applicationGroupID == id {
      updated.mappings[index].applicationGroupID = nil
      updated.mappings[index].appScope = .only(
        group.bundleIdentifiers
      )
    }
    updated.managedApplicationBundleIdentifiers =
      normalizedBundleIdentifiers(
        updated.managedApplicationBundleIdentifiers
          + group.bundleIdentifiers
      )
    apply(updated)
  }

  func addManagedApplication(
    _ bundleIdentifier: String,
    toGroupID groupID: UUID? = nil
  ) {
    let normalized = bundleIdentifier.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalized.isEmpty else { return }
    var updated = database
    updated.managedApplicationBundleIdentifiers =
      normalizedBundleIdentifiers(
        updated.managedApplicationBundleIdentifiers + [normalized]
      )
    moveApplication(
      normalized,
      toGroupID: groupID,
      in: &updated
    )
    apply(updated)
  }

  func moveManagedApplication(
    _ bundleIdentifier: String,
    toGroupID groupID: UUID?
  ) {
    var updated = database
    updated.managedApplicationBundleIdentifiers =
      normalizedBundleIdentifiers(
        updated.managedApplicationBundleIdentifiers
          + [bundleIdentifier]
      )
    moveApplication(
      bundleIdentifier,
      toGroupID: groupID,
      in: &updated
    )
    apply(updated)
  }

  func removeManagedApplication(_ bundleIdentifier: String) {
    var updated = database
    updated.managedApplicationBundleIdentifiers.removeAll {
      $0 == bundleIdentifier
    }
    moveApplication(
      bundleIdentifier,
      toGroupID: nil,
      in: &updated
    )
    apply(updated)
  }

  func setMappingsEnabled(ids: Set<UUID>, isEnabled: Bool) {
    mutateLibrary { library in
      for id in ids {
        try library.setEnabled(id: id, isEnabled)
      }
    }
  }

  func deleteMapping(id: UUID) {
    mutateLibrary {
      try $0.delete(id: id)
    }
  }

  func moveMapping(from sourceIndex: Int, to destinationIndex: Int) {
    mutateLibrary {
      try $0.move(from: sourceIndex, to: destinationIndex)
    }
  }

  func duplicateMapping(id: UUID) {
    guard let mapping = mappings.first(where: { $0.id == id }) else {
      return
    }
    _ = createMapping(
      GestureMappingDraft(
        name: String(
          format: String(localized: "%@ Copy"),
          mapping.name
        ),
        templates: mapping.templates,
        action: mapping.action,
        secondaryAction: mapping.secondaryAction,
        appScope: mapping.appScope,
        triggerButton: mapping.triggerButton,
        category: mapping.category,
        applicationGroupID: mapping.applicationGroupID,
        repeatModeEnabled: mapping.repeatModeEnabled,
        deviceScope: mapping.deviceScope,
        isEnabled: false
      )
    )
  }

  func installPresets(_ presets: [GesturePreset]) {
    guard !presets.isEmpty else { return }
    var library = GestureLibrary(database: database)
    let existingIDs = Set(library.database.mappings.map(\.id))
    for preset in presets where !existingIDs.contains(preset.id) {
      library.create(preset.draft, id: preset.id)
    }
    apply(library.database)
  }

  var allActionPresets: [ActionPreset] {
    ActionPresetLibrary.builtIn + customActionPresets
  }

  @discardableResult
  func createCustomActionPreset(
    name: String,
    category: ActionPresetCategory,
    action: GestureAction
  ) -> String? {
    let normalizedName = name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let preset = ActionPreset(
      id: "user.\(UUID().uuidString.lowercased())",
      name: normalizedName,
      category: category,
      action: action,
      keywords: ["custom"],
      isUserDefined: true
    )
    guard preset.isValid, customActionPresets.count < 100 else {
      return nil
    }
    customActionPresets.append(preset)
    preferencesStore.setCustomActionPresets(customActionPresets)
    return preset.id
  }

  func deleteCustomActionPreset(id: String) {
    let previousCount = customActionPresets.count
    customActionPresets.removeAll { $0.id == id }
    guard customActionPresets.count != previousCount else { return }
    favoriteActionPresetIDs.remove(id)
    recentActionPresetIDs.removeAll { $0 == id }
    preferencesStore.setCustomActionPresets(customActionPresets)
    preferencesStore.setFavoriteActionPresetIDs(
      favoriteActionPresetIDs
    )
    preferencesStore.setRecentActionPresetIDs(
      recentActionPresetIDs
    )
  }

  func toggleFavoriteActionPreset(id: String) {
    if favoriteActionPresetIDs.contains(id) {
      favoriteActionPresetIDs.remove(id)
    } else {
      favoriteActionPresetIDs.insert(id)
    }
    preferencesStore.setFavoriteActionPresetIDs(
      favoriteActionPresetIDs
    )
  }

  func recordActionPresetUse(id: String) {
    recentActionPresetIDs.removeAll { $0 == id }
    recentActionPresetIDs.insert(id, at: 0)
    recentActionPresetIDs = Array(
      recentActionPresetIDs.prefix(12)
    )
    preferencesStore.setRecentActionPresetIDs(
      recentActionPresetIDs
    )
  }

  @discardableResult
  func createUserScript(
    copying template: ScriptLibraryItem? = nil
  ) -> UUID? {
    let item = ScriptLibraryItem(
      name:
        template.map {
          String(
            format: String(localized: "%@ Copy"),
            $0.name
          )
        } ?? String(localized: "New Script"),
      summary: template?.summary ?? "",
      category: template?.category ?? .productivity,
      script:
        template?.script
        ?? AutomationScript(
          kind: .appleScript,
          source: "-- Enter AppleScript here"
        )
    )
    var updated = userScriptLibrary
    updated.append(item)
    guard applyScriptLibrary(updated) else { return nil }
    return item.id
  }

  func updateUserScript(_ item: ScriptLibraryItem) {
    var updated = userScriptLibrary
    if let index = updated.firstIndex(where: {
      $0.id == item.id
    }) {
      updated[index] = item
    } else {
      updated.append(item)
    }
    _ = applyScriptLibrary(updated)
  }

  func deleteUserScript(id: UUID) {
    var updated = userScriptLibrary
    updated.removeAll { $0.id == id }
    guard updated.count != userScriptLibrary.count else { return }
    _ = applyScriptLibrary(updated)
  }

  func reloadScriptLibrary() {
    isLoadingScriptLibrary = true
    guard let scriptLibraryStore else {
      isLoadingScriptLibrary = false
      scriptLibraryError = String(
        localized: "Script library storage is unavailable."
      )
      return
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        userScriptLibrary = try await scriptLibraryStore.load()
        scriptLibraryError = nil
      } catch {
        userScriptLibrary = []
        scriptLibraryError = String(
          localized: "The script library could not be loaded."
        )
      }
      isLoadingScriptLibrary = false
    }
  }

  func prepareMappingImport(from sourceURL: URL) {
    guard let mappingStore else {
      mappingStoreError = String(
        localized: "Gesture storage is unavailable."
      )
      return
    }

    isTransferringMappings = true
    mappingTransferMessage = nil
    let previousTask = persistenceTask
    Task { @MainActor [weak self] in
      await previousTask?.value
      guard let self else { return }
      do {
        pendingImportPreview = try await mappingStore.previewImport(
          from: sourceURL,
          mode: .merge
        )
        pendingImportURL = sourceURL
      } catch {
        mappingStoreError = String(
          localized: "Gesture data could not be imported."
        )
      }
      isTransferringMappings = false
    }
  }

  func performPendingImport(mode: MappingImportMode) {
    guard let mappingStore, let sourceURL = pendingImportURL else {
      return
    }
    isTransferringMappings = true
    let previousTask = persistenceTask
    persistenceTask = Task { @MainActor [weak self] in
      await previousTask?.value
      guard let self else { return }
      do {
        let preview = try await mappingStore.previewImport(
          from: sourceURL,
          mode: mode
        )
        let imported = try await mappingStore.importData(
          from: sourceURL,
          mode: mode
        )
        install(imported)
        pendingImportPreview = nil
        pendingImportURL = nil
        canUndoLastImport = true
        mappingTransferMessage = String(
          format: String(
            localized: "Import complete: %d mappings added."
          ),
          preview.mappingsToAdd
        )
      } catch {
        mappingStoreError = String(
          localized: "Gesture data could not be imported."
        )
      }
      isTransferringMappings = false
    }
  }

  func cancelPendingImport() {
    pendingImportPreview = nil
    pendingImportURL = nil
  }

  func undoLastImport() {
    guard let mappingStore, canUndoLastImport else { return }
    isTransferringMappings = true
    persistenceTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let restored = try await mappingStore.undoLastImport()
        install(restored)
        canUndoLastImport = false
        mappingTransferMessage = String(
          localized: "The last import was undone."
        )
      } catch {
        mappingStoreError = String(
          localized: "The last import could not be undone."
        )
      }
      isTransferringMappings = false
    }
  }

  func exportMappings(to destinationURL: URL) {
    guard let mappingStore else {
      mappingStoreError = String(
        localized: "Gesture storage is unavailable."
      )
      return
    }

    isTransferringMappings = true
    mappingTransferMessage = nil
    let pendingSave = persistenceTask
    Task { @MainActor [weak self] in
      await pendingSave?.value
      guard let self else { return }
      do {
        try await mappingStore.exportData(to: destinationURL)
        mappingStoreError = nil
        mappingTransferMessage = String(
          localized: "Gestures exported successfully."
        )
      } catch {
        mappingStoreError = String(
          localized: "Gesture data could not be exported."
        )
      }
      isTransferringMappings = false
    }
  }

  private func mutateLibrary(
    _ mutation: (inout GestureLibrary) throws -> Void
  ) {
    var library = GestureLibrary(database: database)
    do {
      try mutation(&library)
      apply(library.database)
    } catch {
      mappingStoreError = String(
        localized: "Gesture changes could not be saved."
      )
    }
  }

  private func moveApplication(
    _ bundleIdentifier: String,
    toGroupID groupID: UUID?,
    in database: inout GestureDatabase
  ) {
    let normalized = bundleIdentifier.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalized.isEmpty else { return }

    for index in database.applicationGroups.indices {
      database.applicationGroups[index].bundleIdentifiers.removeAll {
        $0 == normalized
      }
    }
    if let groupID,
      let index = database.applicationGroups.firstIndex(where: {
        $0.id == groupID
      })
    {
      database.applicationGroups[index].bundleIdentifiers =
        normalizedBundleIdentifiers(
          database.applicationGroups[index].bundleIdentifiers
            + [normalized]
        )
    }
    synchronizeGroupScopes(in: &database)
  }

  private func synchronizeGroupScopes(
    in database: inout GestureDatabase
  ) {
    let groupsByID = Dictionary(
      uniqueKeysWithValues: database.applicationGroups.map {
        ($0.id, $0)
      }
    )
    for index in database.mappings.indices {
      guard
        let groupID = database.mappings[index].applicationGroupID,
        let group = groupsByID[groupID]
      else {
        continue
      }
      database.mappings[index].appScope = .only(
        group.bundleIdentifiers
      )
    }
  }

  private func normalizedBundleIdentifiers(
    _ bundleIdentifiers: [String]
  ) -> [String] {
    Array(
      Set(
        bundleIdentifiers.map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
      )
    ).sorted()
  }

  private func migrateLegacySidebarConfiguration(
    in loadedDatabase: GestureDatabase
  ) -> GestureDatabase {
    let legacyGroupNames = preferencesStore.gestureSidebarGroups
    let legacyApplications =
      preferencesStore.gestureSidebarApplications
    guard
      loadedDatabase.applicationGroups.isEmpty,
      !legacyGroupNames.isEmpty || !legacyApplications.isEmpty
    else {
      return loadedDatabase
    }

    var migrated = loadedDatabase
    migrated.managedApplicationBundleIdentifiers =
      normalizedBundleIdentifiers(legacyApplications)
    for name in legacyGroupNames {
      let normalizedName = name.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !normalizedName.isEmpty else { continue }
      let group = GestureApplicationGroup(name: normalizedName)
      migrated.applicationGroups.append(group)
      for index in migrated.mappings.indices
      where migrated.mappings[index].category == normalizedName {
        migrated.mappings[index].applicationGroupID = group.id
        migrated.mappings[index].appScope = .only([])
        migrated.mappings[index].category = nil
      }
    }
    preferencesStore.clearGestureSidebarConfiguration()
    return migrated
  }

  private func apply(_ updatedDatabase: GestureDatabase) {
    guard let mappingStore else {
      mappingStoreError = String(
        localized: "Gesture storage is unavailable."
      )
      return
    }
    do {
      try mappingStore.validate(updatedDatabase)
    } catch {
      mappingStoreError = String(
        localized: "Gesture changes could not be saved."
      )
      return
    }

    database = updatedDatabase
    mappings = updatedDatabase.mappings
    gestureApplicationGroups = updatedDatabase.applicationGroups
    managedApplicationBundleIdentifiers =
      updatedDatabase.managedApplicationBundleIdentifiers
    mappingCount = mappings.count
    mappingStoreError = nil
    reconcileSecondaryTriggerConflict()
    eventTapManager.updateMappingSnapshot(
      updatedDatabase.compiledSnapshot
    )

    let previousTask = persistenceTask
    persistenceTask = Task { @MainActor [weak self] in
      await previousTask?.value
      do {
        try await mappingStore.save(updatedDatabase)
      } catch {
        guard let self, database == updatedDatabase else { return }
        let persistedDatabase = await mappingStore.currentDatabase()
        install(persistedDatabase)
        mappingStoreError = String(
          localized: "Gesture changes could not be saved."
        )
      }
    }
  }

  @discardableResult
  private func applyScriptLibrary(
    _ updatedItems: [ScriptLibraryItem]
  ) -> Bool {
    guard let scriptLibraryStore else {
      scriptLibraryError = String(
        localized: "Script library storage is unavailable."
      )
      return false
    }
    do {
      try scriptLibraryStore.validate(updatedItems)
    } catch {
      scriptLibraryError = String(
        localized: "Script library changes could not be saved."
      )
      return false
    }

    userScriptLibrary = updatedItems
    scriptLibraryError = nil
    let previousTask = scriptLibraryPersistenceTask
    scriptLibraryPersistenceTask = Task { @MainActor [weak self] in
      await previousTask?.value
      do {
        try await scriptLibraryStore.save(updatedItems)
      } catch {
        guard let self, userScriptLibrary == updatedItems else {
          return
        }
        userScriptLibrary = await scriptLibraryStore.currentItems()
        scriptLibraryError = String(
          localized: "Script library changes could not be saved."
        )
      }
    }
    return true
  }

  private func install(_ loadedDatabase: GestureDatabase) {
    database = loadedDatabase
    mappings = loadedDatabase.mappings
    gestureApplicationGroups = loadedDatabase.applicationGroups
    managedApplicationBundleIdentifiers =
      loadedDatabase.managedApplicationBundleIdentifiers
    mappingCount = mappings.count
    mappingStoreError = nil
    reconcileSecondaryTriggerConflict()
    eventTapManager.updateMappingSnapshot(
      loadedDatabase.compiledSnapshot
    )
  }

  private func handleEventTapState(_ state: EventTapManagerState) {
    eventTapState = state
    switch state {
    case .running:
      permissionState = permissionCoordinator.recordEventTapCreation(
        succeeded: true
      )
      eventTapManager.setEnabled(isEnabled)
    case .failedToCreateTap:
      permissionState = permissionCoordinator.recordEventTapCreation(
        succeeded: false
      )
    case .stopped, .starting:
      break
    }
  }

  private func handleUpdateCheckResult(_ result: UpdateCheckResult) {
    availableGitHubRelease = nil
    switch result {
    case .upToDate:
      availableUpdate = nil
      updateState = .upToDate
      updateMessage = String(localized: "iGestures is up to date.")
    case .skipped(let version):
      availableUpdate = nil
      updateState = .skipped(version: version)
      updateMessage = String(
        format: String(localized: "Version %@ is currently skipped."),
        version
      )
    case .available(let update):
      availableUpdate = update
      updateState = .available(
        version: update.manifest.version
      )
      updateMessage = String(
        format: String(localized: "Version %@ is available."),
        update.manifest.version
      )
    case .rejected:
      availableUpdate = nil
      updateState = .failed
      updateMessage = String(
        localized:
          "The update check was rejected or could not be completed."
      )
    }
  }

  private func handleGitHubReleaseCheckResult(
    _ result: GitHubReleaseCheckResult
  ) {
    availableUpdate = nil
    switch result {
    case .upToDate:
      availableGitHubRelease = nil
      updateState = .upToDate
      updateMessage = String(localized: "iGestures is up to date.")
    case .skipped(let version):
      availableGitHubRelease = nil
      updateState = .skipped(version: version)
      updateMessage = String(
        format: String(localized: "Version %@ is currently skipped."),
        version
      )
    case .available(let release):
      availableGitHubRelease = release
      updateState = .available(version: release.version)
      updateMessage = String(
        format: String(localized: "Version %@ is available."),
        release.version
      )
    case .rejected:
      availableGitHubRelease = nil
      updateState = .failed
      updateMessage = String(
        localized:
          "The update check was rejected or could not be completed."
      )
    }
  }

  private func observeApplicationActivation() {
    applicationActivationTask = Task { @MainActor [weak self] in
      for await notification in NotificationCenter.default.notifications(
        named: NSWorkspace.didActivateApplicationNotification
      ) {
        guard !Task.isCancelled, let self else { return }
        if let application = notification.userInfo?[
          NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication {
          updateFrontmostApplication(application)
        } else {
          refreshFrontmostApplication()
        }
      }
    }
  }

  private func observeApplicationLifecycle() {
    applicationLifecycleTask = Task { @MainActor [weak self] in
      for await _ in NotificationCenter.default.notifications(
        named: NSApplication.didBecomeActiveNotification
      ) {
        guard !Task.isCancelled, let self else { return }
        refreshPermissions()
        refreshLoginItemStatus()
      }
    }
  }

  private func refreshFrontmostApplication() {
    guard let application = NSWorkspace.shared.frontmostApplication
    else {
      return
    }
    updateFrontmostApplication(application)
  }

  private func updateFrontmostApplication(
    _ application: NSRunningApplication
  ) {
    guard
      application.bundleIdentifier != Bundle.main.bundleIdentifier
    else {
      return
    }
    currentApplicationName = application.localizedName
    currentApplicationBundleIdentifier = application.bundleIdentifier
  }

  private var gestureInputConfiguration: GestureInputConfiguration {
    GestureInputConfiguration(
      triggerButton: triggerButton,
      secondaryTriggerButton: secondaryTriggerButton,
      triggerDuration: triggerDuration,
      isTrackpadGestureEnabled: isTrackpadGestureEnabled,
      trackpadModifiers: trackpadModifiers
    )
  }

  private func reconcileSecondaryTriggerConflict() {
    guard
      let secondaryTriggerButton,
      mappings.contains(where: {
        $0.triggerButton == secondaryTriggerButton
      })
    else {
      return
    }
    self.secondaryTriggerButton = nil
    preferencesStore.setSecondaryTriggerButton(nil)
    triggerConfigurationError = String(
      localized:
        "The saved secondary trigger conflicted with a gesture and was disabled."
    )
    eventTapManager.updateInputConfiguration(
      gestureInputConfiguration
    )
  }
}

extension GestureTrailColor {
  fileprivate var nsColor: NSColor {
    NSColor(
      srgbRed: red,
      green: green,
      blue: blue,
      alpha: 1
    )
  }
}
