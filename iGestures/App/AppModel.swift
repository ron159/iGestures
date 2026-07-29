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
final class AppModel: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published private(set) var isOverlayEnabled = true
  @Published private(set) var triggerButton: GestureTriggerButton = .right
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
  @Published private(set) var compoundBindings: [CompoundGestureBinding] = []
  @Published private(set) var mappingStoreError: String?
  @Published private(set) var isLoadingMappings = true
  @Published private(set) var loginItemState: LoginItemState
  @Published private(set) var loginItemError: String?
  @Published private(set) var isTransferringMappings = false
  @Published private(set) var mappingTransferMessage: String?
  @Published private(set) var pendingImportPreview: MappingImportPreview?
  @Published private(set) var canUndoLastImport = false
  @Published private(set) var applicationExclusions: Set<ApplicationExclusionRule> = []
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
  private let overlayController: OverlayController
  private let diagnosticsBuffer: GestureDiagnosticsBuffer
  private let updateService: UpdateService?
  private let updateInstaller: UpdatePackageInstaller
  private let updateManifestURL: URL?
  private var availableUpdate: VerifiedUpdate?
  private var database = GestureDatabase.empty
  private var persistenceTask: Task<Void, Never>?
  private var applicationActivationTask: Task<Void, Never>?
  private var applicationLifecycleTask: Task<Void, Never>?
  private var pendingImportURL: URL?

  init(
    permissionCoordinator: PermissionCoordinator? = nil,
    preferencesStore: AppPreferencesStore? = nil,
    loginItemController: LoginItemController? = nil,
    eventTapManager: EventTapManager? = nil,
    mappingStore: MappingStore? = nil
  ) {
    let overlayController = OverlayController()
    self.permissionCoordinator =
      permissionCoordinator ?? PermissionCoordinator()
    let preferencesStore =
      preferencesStore ?? AppPreferencesStore()
    self.preferencesStore = preferencesStore
    self.isEnabled = preferencesStore.recognitionEnabled
    self.isOverlayEnabled = preferencesStore.overlayEnabled
    self.triggerButton = preferencesStore.triggerButton
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
      ) as? String ?? "0"
    let updateService = publicKey.flatMap {
      UpdateService(
        currentVersion: currentVersion,
        publicKeyBase64: $0,
        skippedVersion: preferencesStore.skippedUpdateVersion
      )
    }
    self.updateManifestURL = manifestURL
    self.updateService = updateService
    self.updateInstaller = UpdatePackageInstaller()
    self.updateState =
      updateService == nil || manifestURL == nil
      ? .unavailable
      : .idle
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
    overlayController.eventSink.setEnabled(isOverlayEnabled)
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
    if updateService != nil, manifestURL != nil {
      checkForUpdates()
    }
  }

  deinit {
    applicationActivationTask?.cancel()
    applicationLifecycleTask?.cancel()
    persistenceTask?.cancel()
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
    guard let updateService, let updateManifestURL else {
      if manual {
        updateState = .unavailable
        updateMessage = String(
          localized:
            "Updates are available only in the notarized product build."
        )
      }
      return
    }
    updateState = .checking
    updateMessage = nil
    Task { @MainActor [weak self] in
      let result = await updateService.check(
        manifestURL: updateManifestURL
      )
      guard let self else { return }
      handleUpdateCheckResult(result)
    }
  }

  func skipAvailableUpdate() {
    guard let availableUpdate, let updateService else { return }
    let version = availableUpdate.manifest.version
    Task {
      await updateService.skip(version: version)
    }
    preferencesStore.setSkippedUpdateVersion(version)
    self.availableUpdate = nil
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

  func setTriggerButton(_ triggerButton: GestureTriggerButton) {
    self.triggerButton = triggerButton
    preferencesStore.setTriggerButton(triggerButton)
    eventTapManager.updateInputConfiguration(
      gestureInputConfiguration
    )
  }

  func setTriggerDuration(_ duration: TimeInterval) {
    let configuration = GestureInputConfiguration(
      triggerButton: triggerButton,
      triggerDuration: duration
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
        let database = try await mappingStore.load()
        install(database)
        canUndoLastImport = await mappingStore.canUndoLastImport()
        isLoadingMappings = false
      } catch {
        database = .empty
        mappings = []
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
  func createMapping(_ draft: GestureMappingDraft) -> UUID {
    var library = GestureLibrary(database: database)
    let id = library.create(draft)
    apply(library.database)
    return id
  }

  func updateMapping(
    id: UUID,
    with draft: GestureMappingDraft
  ) {
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

  func setMappingAppScope(id: UUID, appScope: AppScope) {
    mutateLibrary {
      try $0.setAppScope(id: id, appScope)
    }
  }

  func setMappingTriggerButton(
    id: UUID,
    triggerButton: GestureTriggerButton?
  ) {
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
        appScope: mapping.appScope,
        triggerButton: mapping.triggerButton,
        category: mapping.category,
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

  func addCompoundBinding(_ input: CompoundGestureInput) {
    var updated = database
    updated.compoundBindings.append(
      CompoundGestureBinding(
        name: String(localized: "New Compound Gesture"),
        input: input,
        action: .system(.missionControl),
        priority: updated.compoundBindings.count
      )
    )
    apply(updated)
  }

  func updateCompoundBinding(
    id: UUID,
    isEnabled: Bool? = nil,
    action: GestureAction? = nil
  ) {
    guard
      let index = database.compoundBindings.firstIndex(
        where: { $0.id == id }
      )
    else {
      return
    }
    var updated = database
    if let isEnabled {
      updated.compoundBindings[index].isEnabled = isEnabled
    }
    if let action {
      updated.compoundBindings[index].action = action
      if !action.isValid {
        updated.compoundBindings[index].isEnabled = false
      }
    }
    apply(updated)
  }

  func deleteCompoundBinding(id: UUID) {
    var updated = database
    updated.compoundBindings.removeAll { $0.id == id }
    for index in updated.compoundBindings.indices {
      updated.compoundBindings[index].priority = index
    }
    apply(updated)
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
    compoundBindings = updatedDatabase.compoundBindings
    mappingCount = mappings.count
    mappingStoreError = nil
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

  private func install(_ loadedDatabase: GestureDatabase) {
    database = loadedDatabase
    mappings = loadedDatabase.mappings
    compoundBindings = loadedDatabase.compoundBindings
    mappingCount = mappings.count
    mappingStoreError = nil
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
      triggerDuration: triggerDuration,
      isTrackpadGestureEnabled: isTrackpadGestureEnabled,
      trackpadModifiers: trackpadModifiers
    )
  }
}
