import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published private(set) var isOverlayEnabled = true
  @Published private(set) var permissionState: PermissionState = .unknown
  @Published private(set) var eventTapState: EventTapManagerState = .stopped
  @Published private(set) var mappingCount = 0
  @Published private(set) var mappings: [GestureMapping] = []
  @Published private(set) var mappingStoreError: String?
  @Published private(set) var isLoadingMappings = true
  @Published private(set) var loginItemState: LoginItemState
  @Published private(set) var loginItemError: String?
  @Published private(set) var isTransferringMappings = false
  @Published private(set) var mappingTransferMessage: String?

  private let permissionCoordinator: PermissionCoordinator
  private let preferencesStore: AppPreferencesStore
  private let loginItemController: LoginItemController
  private let eventTapManager: EventTapManager
  private let mappingStore: MappingStore?
  private let overlayController: OverlayController
  private var database = GestureDatabase.empty
  private var persistenceTask: Task<Void, Never>?
  private var applicationActivationTask: Task<Void, Never>?

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
    let loginItemController =
      loginItemController ?? LoginItemController()
    self.loginItemController = loginItemController
    self.loginItemState = loginItemController.state
    self.overlayController = overlayController
    self.eventTapManager =
      eventTapManager
      ?? EventTapManager(overlaySink: overlayController.eventSink)
    self.mappingStore =
      mappingStore
      ?? (try? MappingStore.live(
        bundleIdentifier: Bundle.main.bundleIdentifier
          ?? "com.ron159.igestures.dev"
      ))
    overlayController.eventSink.setEnabled(isOverlayEnabled)
    self.eventTapManager.setStateHandler { [weak self] state in
      Task { @MainActor [weak self] in
        self?.handleEventTapState(state)
      }
    }
    observeApplicationActivation()
    refreshPermissions()
    reloadMappings()
  }

  deinit {
    applicationActivationTask?.cancel()
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

  func setMappingAppScope(id: UUID, appScope: AppScope) {
    mutateLibrary {
      try $0.setAppScope(id: id, appScope)
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

  func importMappings(from sourceURL: URL) {
    guard let mappingStore else {
      mappingStoreError = String(
        localized: "Gesture storage is unavailable."
      )
      return
    }

    isTransferringMappings = true
    mappingTransferMessage = nil
    let previousTask = persistenceTask
    persistenceTask = Task { @MainActor [weak self] in
      await previousTask?.value
      guard let self else { return }
      do {
        let imported = try await mappingStore.importData(
          from: sourceURL
        )
        install(imported)
        mappingTransferMessage = String(
          localized: "Gestures imported successfully."
        )
      } catch {
        mappingStoreError = String(
          localized: "Gesture data could not be imported."
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

  private func observeApplicationActivation() {
    applicationActivationTask = Task { @MainActor [weak self] in
      for await _ in NotificationCenter.default.notifications(
        named: NSApplication.didBecomeActiveNotification
      ) {
        guard !Task.isCancelled, let self else { return }
        refreshPermissions()
        refreshLoginItemStatus()
      }
    }
  }
}
