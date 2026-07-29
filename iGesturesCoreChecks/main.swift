import Foundation
import iGestures

@MainActor
private final class CoreChecks {
  private let normalizer = GestureNormalizer()
  private let shortcut = KeyboardShortcut(keyCode: 1, modifiers: 1 << 20)
  private var failures: [String] = []

  func run() async throws {
    try checkNormalizationInvariants()
    try checkRecognitionDecisions()
    try checkBoundedMappingScan()
    checkGestureSession()
    checkPermissionCoordinator()
    checkPreferencesStore()
    try checkLoginItemController()
    checkShortcutEventSequence()
    try await checkMappingStore()
    checkOverlayBuffer()
    try checkGestureLibraryAndTraining()
    checkShortcutRecording()
    checkSystemShortcutConflicts()

    guard failures.isEmpty else {
      fatalError(
        "iGestures core checks failed:\n- "
          + failures.joined(separator: "\n- ")
      )
    }
    print("iGestures core checks passed")
  }

  private func checkNormalizationInvariants() throws {
    let source = chevron(scale: 1, samplesPerSegment: 40)
    let translated = source.map {
      GesturePoint(x: $0.x + 500, y: $0.y - 200)
    }
    let scaled = source.map {
      GesturePoint(x: $0.x * 4, y: $0.y * 4)
    }
    let normalized = try normalizer.normalize(source)
    let variableSpeed = chevronByProgress(
      count: 120,
      progress: { powf($0, 3) }
    )

    check(
      templatesAreEqual(
        normalized,
        try normalizer.normalize(translated)
      ),
      "translation changed the normalized gesture"
    )
    check(
      templatesAreEqual(
        normalized,
        try normalizer.normalize(scaled)
      ),
      "uniform scale changed the normalized gesture"
    )
    check(
      templatesAreEqual(
        try normalizer.normalize(
          chevronByProgress(count: 120, progress: { $0 })
        ),
        try normalizer.normalize(variableSpeed),
        accuracy: 0.01
      ),
      "drawing speed changed the normalized gesture"
    )

    let noisy = source.enumerated().map { index, point in
      GesturePoint(
        x: point.x + (sinf(Float(index) * 1.7) * 1.2),
        y: point.y + (cosf(Float(index) * 1.3) * 1.2)
      )
    }
    check(
      GestureRecognizer().distance(
        from: normalized,
        to: try normalizer.normalize(noisy)
      ) < 0.08,
      "small input noise exceeded the recognition tolerance"
    )

    let horizontal = try template(angle: 0)
    let vertical = try template(angle: .pi / 2)
    let reverse = try normalizer.normalize(
      line(from: (160, 0), to: (0, 0), count: 80)
    )
    let recognizer = GestureRecognizer()

    check(
      horizontal.points.allSatisfy {
        $0.x.isFinite && $0.y.isFinite
      },
      "horizontal normalization produced a non-finite point"
    )
    check(
      vertical.points.allSatisfy {
        $0.x.isFinite && $0.y.isFinite
      },
      "vertical normalization produced a non-finite point"
    )
    check(
      recognizer.distance(from: horizontal, to: vertical) > 0.1,
      "rotation was not preserved"
    )
    check(
      recognizer.distance(from: horizontal, to: reverse) > 0.1,
      "stroke direction was not preserved"
    )
  }

  private func checkRecognitionDecisions() throws {
    let recognizer = GestureRecognizer()
    let horizontal = try template(angle: 0)
    let vertical = try template(angle: .pi / 2)
    let horizontalID = UUID()
    let mappings = [
      mapping(id: UUID(), template: vertical, priority: 0),
      mapping(id: horizontalID, template: horizontal, priority: 1),
    ]

    let decision = recognizer.recognize(
      horizontal,
      mappings: mappings,
      frontmostBundleID: "com.apple.finder"
    )
    if case .matched(let match) = decision {
      check(
        match.mappingID == horizontalID,
        "the nearest template did not win"
      )
    } else {
      check(false, "an exact template did not match")
    }

    let rejected = GestureRecognizer(
      configuration: .init(acceptanceThreshold: 0.01)
    ).recognize(
      horizontal,
      mappings: [mapping(id: UUID(), template: vertical)],
      frontmostBundleID: nil
    )
    check(rejected == .noMatch, "the acceptance threshold did not reject")

    let ambiguous = GestureRecognizer(
      configuration: .init(
        acceptanceThreshold: 1,
        ambiguityMargin: 1
      )
    ).recognize(
      horizontal,
      mappings: [
        mapping(id: UUID(), template: try template(angle: 0.1)),
        mapping(id: UUID(), template: vertical),
      ],
      frontmostBundleID: nil
    )
    if case .ambiguous = ambiguous {
      // Expected.
    } else {
      check(false, "a close second candidate was not rejected")
    }

    let scoped = GestureMapping(
      name: "Scoped",
      templates: [horizontal],
      shortcut: shortcut,
      appScope: .allExcept(["com.apple.Safari"])
    )
    check(
      recognizer.recognize(
        horizontal,
        mappings: [scoped],
        frontmostBundleID: "com.apple.Safari"
      ) == .noMatch
        && recognizer.recognize(
          horizontal,
          mappings: [scoped],
          frontmostBundleID: nil
        ) == .noMatch,
      "all-except scope did not fail closed"
    )
  }

  private func checkBoundedMappingScan() throws {
    let candidate = try template(angle: 0)
    let mappings = try (0..<100).map { index in
      GestureMapping(
        name: "Gesture \(index)",
        templates: [
          try template(angle: Float(index) * 0.01),
          try template(angle: Float(index) * 0.01 + 0.02),
          try template(angle: Float(index) * 0.01 - 0.02),
        ],
        shortcut: shortcut,
        appScope: .all,
        priority: index
      )
    }
    let recognizer = GestureRecognizer()
    _ = recognizer.recognize(
      candidate,
      mappings: mappings,
      frontmostBundleID: nil
    )
    var samples: [Duration] = []
    samples.reserveCapacity(100)
    for _ in 0..<100 {
      let start = ContinuousClock.now
      _ = recognizer.recognize(
        candidate,
        mappings: mappings,
        frontmostBundleID: nil
      )
      samples.append(ContinuousClock.now - start)
    }
    let p95 = samples.sorted()[94]
    #if DEBUG
      let maximumP95 = Duration.milliseconds(30)
    #else
      let maximumP95 = Duration.milliseconds(2)
    #endif
    check(
      p95 < maximumP95,
      "the 100 mapping recognition P95 exceeded its build threshold"
    )
  }

  private func checkGestureSession() {
    var session = GestureSession(
      configuration: .init(activationDistance: 20)
    )
    let down = session.mouseDown(
      at: GesturePoint(x: 0, y: 0),
      timestamp: 0,
      frontmostBundleID: "com.apple.finder",
      shouldTrack: true
    )
    check(
      down.disposition == .suppress
        && session.state == .pendingClick,
      "right mouse down did not start a pending session"
    )

    let drag = session.mouseDragged(
      to: GesturePoint(x: 30, y: 0),
      timestamp: 0.1
    )
    check(
      drag.commands.first
        == .showOverlay(at: GesturePoint(x: 0, y: 0))
        && session.state == .tracking,
      "crossing the dead zone did not start tracking"
    )

    let up = session.mouseUp(
      at: GesturePoint(x: 40, y: 0),
      timestamp: 0.2
    )
    check(
      up.commands.contains(where: {
        if case .recognize = $0 { return true }
        return false
      }) && session.state == .idle,
      "mouse up did not finish and reset the gesture session"
    )
    check(
      session.mouseUp(
        at: GesturePoint(x: 40, y: 0),
        timestamp: 0.3
      ) == .passThrough,
      "a second mouse up completed the session twice"
    )

    _ = session.mouseDown(
      at: GesturePoint(x: 10, y: 10),
      timestamp: 1,
      frontmostBundleID: nil,
      shouldTrack: true
    )
    let failure = session.cancel(
      .tapDisabledByTimeout,
      at: GesturePoint(x: 10, y: 10)
    )
    check(
      failure.commands.contains(
        .replayPendingClick(
          mouseUpLocation: GesturePoint(x: 10, y: 10)
        )
      ) && session.state == .idle,
      "tap timeout did not fail open"
    )

    var durationLimited = GestureSession(
      configuration: .init(maximumDuration: 0.1)
    )
    _ = durationLimited.mouseDown(
      at: GesturePoint(x: 0, y: 0),
      timestamp: 1,
      frontmostBundleID: nil,
      shouldTrack: true
    )
    let durationFailure = durationLimited.mouseDragged(
      to: GesturePoint(x: 30, y: 0),
      timestamp: 1.2
    )
    check(
      durationFailure.commands.contains(
        .didFailOpen(.durationExceeded)
      ) && durationLimited.state == .idle,
      "an overlong gesture did not fail open"
    )

    var triggerDelayed = GestureSession(
      configuration: .init(
        activationDistance: 20,
        minimumTriggerDuration: 0.2
      )
    )
    _ = triggerDelayed.mouseDown(
      at: GesturePoint(x: 0, y: 0),
      timestamp: 0,
      frontmostBundleID: nil,
      shouldTrack: true
    )
    let earlyDrag = triggerDelayed.mouseDragged(
      to: GesturePoint(x: 10, y: 0),
      timestamp: 0.1
    )
    let activatedDrag = triggerDelayed.mouseDragged(
      to: GesturePoint(x: 11, y: 0),
      timestamp: 0.2
    )
    check(
      earlyDrag.commands.isEmpty
        && activatedDrag.commands.contains(
          .showOverlay(at: GesturePoint(x: 0, y: 0))
        ),
      "the hold duration did not independently activate gesture tracking"
    )

    var movementActivated = GestureSession(
      configuration: .init(
        activationDistance: 20,
        minimumTriggerDuration: 0.2
      )
    )
    _ = movementActivated.mouseDown(
      at: GesturePoint(x: 0, y: 0),
      timestamp: 0,
      frontmostBundleID: nil,
      shouldTrack: true
    )
    let fastDrag = movementActivated.mouseDragged(
      to: GesturePoint(x: 30, y: 0),
      timestamp: 0.1
    )
    check(
      fastDrag.commands.contains(
        .showOverlay(at: GesturePoint(x: 0, y: 0))
      ),
      "the movement threshold did not independently activate gesture tracking"
    )
  }

  private func checkPermissionCoordinator() {
    let provider = PermissionProviderCheckStub(
      value: PermissionDiagnostics(
        accessibilityTrusted: false,
        listenEventAccess: false,
        postEventAccess: false
      )
    )
    let coordinator = PermissionCoordinator(provider: provider)

    check(
      coordinator.refresh() == .needsUserAction
        && provider.promptValues == [false],
      "initial permission state was not actionable"
    )
    check(
      coordinator.requestAccess() == .checking
        && provider.promptValues == [false, true],
      "permission prompt was not explicitly requested"
    )
    check(
      coordinator.refresh() == .denied
        && provider.promptValues == [false, true, false],
      "denied permission did not settle without another prompt"
    )
    check(
      coordinator.recordEventTapCreation(succeeded: false)
        == .tapCreationFailed,
      "event tap failure was not surfaced"
    )
  }

  private func checkPreferencesStore() {
    let suiteName = "iGesturesCoreChecks.\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
      check(false, "preferences test suite could not be created")
      return
    }
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    let store = AppPreferencesStore(userDefaults: userDefaults)
    check(
      store.recognitionEnabled
        && store.overlayEnabled
        && store.triggerButton == .right
        && store.triggerDuration
          == GestureInputConfiguration.defaultTriggerDuration,
      "general preferences did not use enabled defaults"
    )
    store.setRecognitionEnabled(false)
    store.setOverlayEnabled(false)
    store.setTriggerButton(
      GestureTriggerButton(buttonNumber: 8)
    )
    store.setTriggerDuration(0.4)
    let reloaded = AppPreferencesStore(userDefaults: userDefaults)
    check(
      !reloaded.recognitionEnabled
        && !reloaded.overlayEnabled
        && reloaded.triggerButton
          == GestureTriggerButton(buttonNumber: 8)
        && reloaded.triggerDuration == 0.4,
      "general preferences did not persist"
    )
  }

  private func checkLoginItemController() throws {
    let provider = LoginItemProviderCheckStub(state: .notRegistered)
    let controller = LoginItemController(provider: provider)
    check(
      try controller.setEnabled(true) == .enabled
        && provider.registerCount == 1,
      "login item registration did not update state"
    )
    check(
      try controller.setEnabled(false) == .notRegistered
        && provider.unregisterCount == 1,
      "login item unregistration did not update state"
    )
  }

  private func checkShortcutEventSequence() {
    let shortcut = KeyboardShortcut(
      keyCode: 12,
      modifiers: 0x18_0000
    )
    let events = SystemShortcutExecutor.eventSequence(for: shortcut)

    check(
      events.count == 2
        && events[0].isKeyDown
        && !events[1].isKeyDown
        && events.allSatisfy {
          $0.sourceUserData
            == EventSourceMarker.syntheticEventUserData
        },
      "shortcut execution did not produce a marked key pair"
    )
  }

  private func checkMappingStore() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }

    let original = GestureDatabase(
      mappings: [
        GestureMapping(
          name: "Original",
          templates: [try template(angle: 0)],
          shortcut: shortcut,
          appScope: .only(["com.apple.finder"])
        )
      ]
    )
    let replacement = GestureDatabase(
      mappings: [
        GestureMapping(
          name: "Replacement",
          templates: [try template(angle: .pi / 2)],
          shortcut: shortcut,
          appScope: .allExcept(["com.apple.Safari"])
        )
      ]
    )
    let store = MappingStore(directoryURL: directoryURL)
    try await store.save(original)
    try await store.save(replacement)

    check(
      try await MappingStore(directoryURL: directoryURL).load()
        == replacement,
      "mapping store did not round-trip"
    )

    let exportURL = directoryURL.appendingPathComponent("export.json")
    try await store.exportData(to: exportURL)
    let imported = try await MappingStore(
      directoryURL: directoryURL.appendingPathComponent(
        "imported",
        isDirectory: true
      )
    ).importData(from: exportURL)
    check(
      imported == replacement,
      "mapping file import/export did not round-trip"
    )

    var invalidPriority = replacement
    invalidPriority.mappings[0].priority = 2
    do {
      try await store.save(invalidPriority)
      check(false, "mapping store accepted an invalid priority")
    } catch {
      check(
        error as? MappingStoreError == .invalidPriority,
        "mapping store returned the wrong priority validation error"
      )
    }

    var invalidFlags = replacement
    invalidFlags.mappings[0].shortcut = KeyboardShortcut(
      keyCode: 12,
      modifiers: 1
    )
    do {
      try await store.save(invalidFlags)
      check(false, "mapping store accepted shortcut flag garbage")
    } catch {
      check(
        error as? MappingStoreError == .invalidShortcut,
        "mapping store returned the wrong shortcut validation error"
      )
    }

    try Data("corrupt".utf8).write(to: store.fileURL)
    check(
      try await MappingStore(directoryURL: directoryURL).load()
        == original,
      "mapping store did not recover the last successful backup"
    )
  }

  private func checkOverlayBuffer() {
    let buffer = OverlayEventBuffer()
    buffer.show(at: GesturePoint(x: 0, y: 0))
    buffer.append(GesturePoint(x: 1, y: 1))
    buffer.append(GesturePoint(x: 2, y: 2))

    check(
      buffer.drain()
        == OverlayUpdateBatch(
          startPoint: GesturePoint(x: 0, y: 0),
          points: [
            GesturePoint(x: 1, y: 1),
            GesturePoint(x: 2, y: 2),
          ],
          shouldHide: false
        ),
      "overlay events were not coalesced into one display update"
    )

    buffer.hide()
    check(
      buffer.drain()?.shouldHide == true,
      "overlay hide was not delivered"
    )

    buffer.show(at: GesturePoint(x: 3, y: 3))
    buffer.setEnabled(false)
    check(
      buffer.drain()?.shouldHide == true,
      "disabling the overlay did not hide an active path"
    )
    buffer.show(at: GesturePoint(x: 4, y: 4))
    check(
      buffer.drain() == nil,
      "disabled overlay accepted a new path"
    )
  }

  private func checkGestureLibraryAndTraining() throws {
    let template = try template(angle: 0)
    var library = GestureLibrary()
    let firstID = library.create(
      GestureMappingDraft(
        name: "First",
        templates: [template],
        shortcut: shortcut
      )
    )
    _ = library.create(
      GestureMappingDraft(
        name: "Second",
        templates: [try self.template(angle: .pi / 2)],
        shortcut: shortcut
      )
    )
    try library.move(from: 1, to: 0)
    try library.rename(id: firstID, to: "Renamed")
    check(
      library.database.mappings.map(\.priority) == [0, 1]
        && library.database.mappings[1].name == "Renamed",
      "gesture CRUD did not preserve deterministic priorities"
    )
    try library.setShortcut(
      id: firstID,
      ShortcutRecordingSession.emptyShortcut
    )
    check(
      !library.database.mappings[1].isEnabled,
      "clearing a shortcut did not disable its mapping"
    )
    let replacementTemplate = try self.template(angle: Float.pi)
    try library.update(
      id: firstID,
      with: GestureMappingDraft(
        name: "Retrained",
        templates: [replacementTemplate],
        shortcut: shortcut,
        appScope: .only(["com.apple.finder"])
      )
    )
    check(
      library.database.mappings[1].name == "Retrained"
        && library.database.mappings[1].templates
          == [replacementTemplate],
      "retraining did not replace the mapping draft"
    )

    var training = GestureTrainingSession(existingMappings: [])
    _ = training.recordSample(trainingLine(angle: 0, offset: 0))
    _ = training.recordSample(trainingLine(angle: 0, offset: 40))
    check(
      training.recordSample(trainingLine(angle: 0, offset: 80))
        == .readyForTesting(requiredSuccessfulTests: 2),
      "three consistent samples did not enter testing"
    )
    _ = training.recordTest(trainingLine(angle: 0.01, offset: 0))
    check(
      training.recordTest(trainingLine(angle: -0.01, offset: 0))
        == .readyToSave,
      "successful training tests did not become saveable"
    )
  }

  private func checkShortcutRecording() {
    var recording = ShortcutRecordingSession(shortcut: shortcut)
    recording.begin()
    let recorded = recording.handleKeyDown(
      keyCode: 12,
      modifiers: (1 << 20) | (1 << 16)
    )
    check(
      recorded
        == .recorded(
          KeyboardShortcut(keyCode: 12, modifiers: 1 << 20)
        ),
      "shortcut recording did not normalize modifier flags"
    )

    var cancellation = ShortcutRecordingSession(shortcut: shortcut)
    cancellation.begin()
    check(
      cancellation.handleKeyDown(keyCode: 53, modifiers: 0)
        == .cancelled
        && cancellation.shortcut == shortcut,
      "Escape did not cancel shortcut recording"
    )

    var clearing = ShortcutRecordingSession(shortcut: shortcut)
    clearing.begin()
    check(
      clearing.handleKeyDown(keyCode: 51, modifiers: 0)
        == .cleared
        && !clearing.shortcut.isValid,
      "Delete did not clear shortcut recording"
    )

    var capture = ShortcutCaptureState()
    capture.begin()
    check(
      capture.handleKeyDown(keyCode: 49, modifiers: 1 << 20)
        == .captured(keyCode: 49, modifiers: 1 << 20)
        && capture.handleKeyDown(keyCode: 49, modifiers: 1 << 20)
          == .suppress
        && capture.handleKeyUp(keyCode: 49) == .suppress
        && capture.handleKeyUp(keyCode: 49) == .passThrough,
      "shortcut capture did not suppress the recorded key lifecycle"
    )
  }

  private func checkSystemShortcutConflicts() {
    let detector = SystemShortcutConflictDetector()
    check(
      detector.conflict(
        for: KeyboardShortcut(
          keyCode: 49,
          modifiers: 1 << 20
        )
      ) == .spotlight,
      "a common system shortcut conflict was not reported"
    )
    check(
      detector.conflict(
        for: KeyboardShortcut(
          keyCode: 12,
          modifiers: 1 << 20
        )
      ) == nil,
      "an ordinary shortcut was reported as reserved"
    )
  }

  private func check(_ condition: Bool, _ message: String) {
    if !condition {
      failures.append(message)
    }
  }

  private func templatesAreEqual(
    _ left: GestureTemplate,
    _ right: GestureTemplate,
    accuracy: Float = 0.0001
  ) -> Bool {
    guard left.points.count == right.points.count,
      abs(left.aspectRatio - right.aspectRatio) <= accuracy
    else {
      return false
    }
    return zip(left.points, right.points).allSatisfy {
      abs($0.x - $1.x) <= accuracy
        && abs($0.y - $1.y) <= accuracy
    }
  }

  private func mapping(
    id: UUID,
    template: GestureTemplate,
    priority: Int = 0
  ) -> GestureMapping {
    GestureMapping(
      id: id,
      name: "Check",
      templates: [template],
      shortcut: shortcut,
      appScope: .all,
      priority: priority
    )
  }

  private func template(angle: Float) throws -> GestureTemplate {
    let cosine = cosf(angle)
    let sine = sinf(angle)
    let points = (0..<80).map { index in
      let distance = Float(index) * 2
      return GesturePoint(
        x: cosine * distance,
        y: sine * distance
      )
    }
    return try normalizer.normalize(points)
  }

  private func line(
    from start: (Float, Float),
    to end: (Float, Float),
    count: Int
  ) -> [GesturePoint] {
    (0..<count).map { index in
      let fraction = Float(index) / Float(count - 1)
      return GesturePoint(
        x: start.0 + ((end.0 - start.0) * fraction),
        y: start.1 + ((end.1 - start.1) * fraction)
      )
    }
  }

  private func chevron(
    scale: Float,
    samplesPerSegment: Int
  ) -> [GesturePoint] {
    let first = line(
      from: (0, 80 * scale),
      to: (60 * scale, 0),
      count: samplesPerSegment
    )
    let second = line(
      from: (60 * scale, 0),
      to: (120 * scale, 80 * scale),
      count: samplesPerSegment
    )
    return first + second.dropFirst()
  }

  private func trainingLine(
    angle: Float,
    offset: Float
  ) -> [GesturePoint] {
    (0..<80).map { index in
      let distance = Float(index) * 2
      return GesturePoint(
        x: offset + (cosf(angle) * distance),
        y: offset + (sinf(angle) * distance)
      )
    }
  }

  private func chevronByProgress(
    count: Int,
    progress: (Float) -> Float
  ) -> [GesturePoint] {
    (0..<count).map { index in
      let linear = Float(index) / Float(count - 1)
      let value = min(1, max(0, progress(linear)))
      if value <= 0.5 {
        return GesturePoint(
          x: value * 120,
          y: 80 - (value * 160)
        )
      }
      return GesturePoint(
        x: value * 120,
        y: (value - 0.5) * 160
      )
    }
  }
}

private let checks = CoreChecks()
try await checks.run()

@MainActor
private final class PermissionProviderCheckStub: PermissionProviding {
  let value: PermissionDiagnostics
  private(set) var promptValues: [Bool] = []

  init(value: PermissionDiagnostics) {
    self.value = value
  }

  func diagnostics(
    promptForAccessibility: Bool
  ) -> PermissionDiagnostics {
    promptValues.append(promptForAccessibility)
    return value
  }
}

@MainActor
private final class LoginItemProviderCheckStub: LoginItemProviding {
  private(set) var state: LoginItemState
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  init(state: LoginItemState) {
    self.state = state
  }

  func register() {
    registerCount += 1
    state = .enabled
  }

  func unregister() {
    unregisterCount += 1
    state = .notRegistered
  }

  func openSystemSettings() {}
}
