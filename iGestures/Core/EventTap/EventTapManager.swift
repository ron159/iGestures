@preconcurrency import CoreGraphics
import Foundation
import os

public enum EventTapManagerState: Equatable, Sendable {
  case stopped
  case starting
  case running
  case failedToCreateTap
}

public final class EventTapManager: @unchecked Sendable {
  public typealias StateHandler =
    @Sendable (EventTapManagerState) -> Void
  public typealias ShortcutRecordingHandler =
    @Sendable (_ keyCode: UInt16, _ modifiers: UInt64) -> Void
  public typealias TriggerButtonRecordingHandler =
    @Sendable (GestureTriggerButton) -> Void
  public typealias GlobalToggleHandler = @Sendable () -> Void

  private let lifecycleLock = NSLock()
  private static let performanceLog = OSLog(
    subsystem: "com.ron159.igestures",
    category: "Performance"
  )
  private let frontmostAppProvider: any FrontmostAppProviding
  private let actionDispatcher: ActionDispatcher
  private let overlaySink: any GestureOverlaySinking
  private let feedbackSink: any GestureFeedbackSinking
  private let normalizer: GestureNormalizer
  private var recognizer: GestureRecognizer

  private var thread: Thread?
  private var runLoop: CFRunLoop?
  private var pendingSnapshot = CompiledMappingSnapshot.empty
  private var pendingEnabled = false
  private var pendingInputConfiguration =
    GestureInputConfiguration.default
  private var pendingRecognitionConfiguration =
    GestureRecognizer.Configuration()
  private var pendingExclusionRules: Set<ApplicationExclusionRule> = []
  private var stopRequested = false
  private var stateHandler: StateHandler?
  private var shortcutCaptureState = ShortcutCaptureState()
  private var triggerButtonCaptureState = TriggerButtonCaptureState()
  private var shortcutRecording:
    (
      id: UUID, handler: ShortcutRecordingHandler
    )?
  private var triggerButtonRecording:
    (
      id: UUID, handler: TriggerButtonRecordingHandler
    )?
  private var globalToggleShortcut =
    KeyboardShortcut(
      keyCode: 5,
      modifiers:
        CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue
    )
  private var globalToggleHandler: GlobalToggleHandler?

  // The following properties are confined to the Event Tap thread.
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var session = GestureSession()
  private var pendingMouseDown: CGEvent?
  private var pendingSecondaryMouseDown: CGEvent?
  private var activeTriggerButton: GestureTriggerButton?
  private var secondaryTriggerIsDown = false
  private var secondaryTriggerIsPassingThrough = false
  private var activeSessionUsesSecondaryTrigger = false
  private var mappingSnapshot = CompiledMappingSnapshot.empty
  private var isEnabled = false
  private var inputConfiguration = GestureInputConfiguration.default
  private var activeSessionSignpostID: OSSignpostID?
  private var exclusionRules: Set<ApplicationExclusionRule> = []
  private var isSuppressingEscape = false
  private var isSuppressingGlobalToggle = false
  private var suppressedMouseUpButtons: Set<GestureTriggerButton> = []
  private var repeatState: RepeatState?
  private var pendingRepeatRequest: ActionRequest?

  public init(
    frontmostAppProvider: any FrontmostAppProviding =
      SystemFrontmostAppProvider(),
    actionExecutor: any ActionExecuting = SystemGestureActionExecutor(),
    actionResultHandler: ActionDispatcher.ResultHandler? = nil,
    overlaySink: any GestureOverlaySinking = NoOpGestureOverlaySink(),
    feedbackSink: any GestureFeedbackSinking =
      NoOpGestureFeedbackSink(),
    normalizer: GestureNormalizer = GestureNormalizer(),
    recognizer: GestureRecognizer = GestureRecognizer()
  ) {
    self.frontmostAppProvider = frontmostAppProvider
    self.feedbackSink = feedbackSink
    self.actionDispatcher = ActionDispatcher(
      executor: actionExecutor,
      resultHandler: { request, result in
        switch result {
        case .succeeded:
          feedbackSink.show(
            .executed(mappingName: request.mappingName)
          )
        case .failed:
          feedbackSink.show(
            .actionFailed(mappingName: request.mappingName)
          )
        }
        actionResultHandler?(request, result)
      }
    )
    self.overlaySink = overlaySink
    self.normalizer = normalizer
    self.recognizer = recognizer
  }

  public func setStateHandler(_ handler: StateHandler?) {
    lifecycleLock.lock()
    stateHandler = handler
    lifecycleLock.unlock()
  }

  @discardableResult
  public func beginShortcutRecording(
    _ handler: @escaping ShortcutRecordingHandler
  ) -> UUID {
    let id = UUID()
    lifecycleLock.lock()
    triggerButtonRecording = nil
    triggerButtonCaptureState.cancel()
    shortcutCaptureState.begin()
    shortcutRecording = (id, handler)
    lifecycleLock.unlock()
    return id
  }

  public func endShortcutRecording(id: UUID) {
    lifecycleLock.lock()
    if shortcutRecording?.id == id {
      shortcutRecording = nil
      shortcutCaptureState.cancel()
    }
    lifecycleLock.unlock()
  }

  @discardableResult
  public func beginTriggerButtonRecording(
    _ handler: @escaping TriggerButtonRecordingHandler
  ) -> UUID {
    let id = UUID()
    lifecycleLock.lock()
    shortcutRecording = nil
    shortcutCaptureState.cancel()
    triggerButtonCaptureState.begin()
    triggerButtonRecording = (id, handler)
    lifecycleLock.unlock()
    return id
  }

  public func endTriggerButtonRecording(id: UUID) {
    lifecycleLock.lock()
    if triggerButtonRecording?.id == id {
      triggerButtonRecording = nil
      triggerButtonCaptureState.cancel()
    }
    lifecycleLock.unlock()
  }

  public func configureGlobalToggle(
    shortcut: KeyboardShortcut,
    handler: GlobalToggleHandler?
  ) {
    lifecycleLock.lock()
    globalToggleShortcut = shortcut
    globalToggleHandler = handler
    lifecycleLock.unlock()
  }

  public func start() {
    lifecycleLock.lock()
    guard thread == nil else {
      lifecycleLock.unlock()
      return
    }

    stopRequested = false
    let worker = Thread { [self] in
      runEventLoop()
    }
    worker.name = "com.ron159.igestures.event-tap"
    worker.qualityOfService = .userInteractive
    thread = worker
    lifecycleLock.unlock()
    notifyState(.starting)
    worker.start()
  }

  public func stop(
    reason: GestureCancellationReason = .applicationTerminating
  ) {
    lifecycleLock.lock()
    stopRequested = true
    let runLoop = self.runLoop
    lifecycleLock.unlock()

    guard let runLoop else { return }
    CFRunLoopPerformBlock(
      runLoop,
      CFRunLoopMode.defaultMode!.rawValue as CFTypeRef
    ) { [self] in
      let manager = self
      let result = manager.session.cancel(reason)
      manager.apply(result.commands, currentEvent: nil)
      CFRunLoopStop(runLoop)
    }
    CFRunLoopWakeUp(runLoop)
  }

  public func setEnabled(_ enabled: Bool) {
    lifecycleLock.lock()
    pendingEnabled = enabled
    let runLoop = self.runLoop
    lifecycleLock.unlock()

    guard let runLoop else { return }
    CFRunLoopPerformBlock(
      runLoop,
      CFRunLoopMode.defaultMode!.rawValue as CFTypeRef
    ) { [self] in
      let manager = self
      manager.isEnabled = enabled
      if !enabled {
        let result = manager.session.cancel(.disabled)
        manager.apply(result.commands, currentEvent: nil)
        manager.releasePendingSecondaryTrigger()
      }
    }
    CFRunLoopWakeUp(runLoop)
  }

  public func updateMappingSnapshot(
    _ snapshot: CompiledMappingSnapshot
  ) {
    lifecycleLock.lock()
    pendingSnapshot = snapshot
    let runLoop = self.runLoop
    lifecycleLock.unlock()

    guard let runLoop else { return }
    CFRunLoopPerformBlock(
      runLoop,
      CFRunLoopMode.defaultMode!.rawValue as CFTypeRef
    ) { [self] in
      let result = session.cancel(.configurationInvalid)
      apply(result.commands, currentEvent: nil)
      releasePendingSecondaryTrigger()
      mappingSnapshot = snapshot
    }
    CFRunLoopWakeUp(runLoop)
  }

  public func updateInputConfiguration(
    _ configuration: GestureInputConfiguration
  ) {
    lifecycleLock.lock()
    pendingInputConfiguration = configuration
    let runLoop = self.runLoop
    lifecycleLock.unlock()

    guard let runLoop else { return }
    CFRunLoopPerformBlock(
      runLoop,
      CFRunLoopMode.defaultMode!.rawValue as CFTypeRef
    ) { [self] in
      let result = session.cancel(.configurationInvalid)
      apply(result.commands, currentEvent: nil)
      releasePendingSecondaryTrigger()
      inputConfiguration = configuration
      session = GestureSession(
        configuration: .init(
          minimumTriggerDuration: configuration.triggerDuration
        )
      )
    }
    CFRunLoopWakeUp(runLoop)
  }

  public func updateRecognitionSensitivity(
    _ sensitivity: RecognitionSensitivity
  ) {
    let configuration = sensitivity.configuration
    lifecycleLock.lock()
    pendingRecognitionConfiguration = configuration
    let runLoop = self.runLoop
    lifecycleLock.unlock()

    guard let runLoop else { return }
    CFRunLoopPerformBlock(
      runLoop,
      CFRunLoopMode.defaultMode!.rawValue as CFTypeRef
    ) { [self] in
      recognizer = GestureRecognizer(configuration: configuration)
    }
    CFRunLoopWakeUp(runLoop)
  }

  public func updateApplicationExclusions(
    _ rules: Set<ApplicationExclusionRule>
  ) {
    lifecycleLock.lock()
    pendingExclusionRules = rules
    let runLoop = self.runLoop
    lifecycleLock.unlock()

    guard let runLoop else { return }
    CFRunLoopPerformBlock(
      runLoop,
      CFRunLoopMode.defaultMode!.rawValue as CFTypeRef
    ) { [self] in
      let result = session.cancel(.configurationInvalid)
      apply(result.commands, currentEvent: nil)
      releasePendingSecondaryTrigger()
      exclusionRules = rules
    }
    CFRunLoopWakeUp(runLoop)
  }

  private func runEventLoop() {
    autoreleasepool {
      let currentRunLoop = CFRunLoopGetCurrent()
      lifecycleLock.lock()
      runLoop = currentRunLoop
      mappingSnapshot = pendingSnapshot
      isEnabled = pendingEnabled
      inputConfiguration = pendingInputConfiguration
      recognizer = GestureRecognizer(
        configuration: pendingRecognitionConfiguration
      )
      exclusionRules = pendingExclusionRules
      session = GestureSession(
        configuration: .init(
          minimumTriggerDuration: inputConfiguration.triggerDuration
        )
      )
      let shouldStop = stopRequested
      lifecycleLock.unlock()

      if shouldStop {
        finishEventLoop()
        notifyState(.stopped)
        return
      }

      let mask = Self.eventMask
      guard
        let tap = CGEvent.tapCreate(
          tap: .cgSessionEventTap,
          place: .headInsertEventTap,
          options: .defaultTap,
          eventsOfInterest: mask,
          callback: eventTapCallback,
          userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
      else {
        notifyState(.failedToCreateTap)
        finishEventLoop()
        return
      }

      let source = CFMachPortCreateRunLoopSource(
        kCFAllocatorDefault,
        tap,
        0
      )
      eventTap = tap
      runLoopSource = source
      CFRunLoopAddSource(currentRunLoop, source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
      notifyState(.running)
      CFRunLoopRun()

      let result = session.cancel(.applicationTerminating)
      apply(result.commands, currentEvent: nil)
      releasePendingSecondaryTrigger()
      if let runLoopSource {
        CFRunLoopRemoveSource(
          currentRunLoop,
          runLoopSource,
          .commonModes
        )
      }
      CFMachPortInvalidate(tap)
      eventTap = nil
      runLoopSource = nil
      finishEventLoop()
      notifyState(.stopped)
    }
  }

  private func finishEventLoop() {
    lifecycleLock.lock()
    runLoop = nil
    thread = nil
    shortcutRecording = nil
    shortcutCaptureState.reset()
    triggerButtonRecording = nil
    triggerButtonCaptureState.reset()
    lifecycleLock.unlock()
  }

  fileprivate func handle(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    if type == .keyDown || type == .keyUp {
      return handleShortcutEvent(type: type, event: event)
    }
    if type == .mouseMoved,
      activeTriggerButton?.keyboardKeyCode == nil
    {
      return Unmanaged.passUnretained(event)
    }

    let signpostID = OSSignpostID(log: Self.performanceLog)
    os_signpost(
      .begin,
      log: Self.performanceLog,
      name: "EventTapCallback",
      signpostID: signpostID
    )
    defer {
      os_signpost(
        .end,
        log: Self.performanceLog,
        name: "EventTapCallback",
        signpostID: signpostID
      )
    }

    if type == .tapDisabledByTimeout
      || type == .tapDisabledByUserInput
    {
      let reason: GestureCancellationReason =
        type == .tapDisabledByTimeout
        ? .tapDisabledByTimeout
        : .tapDisabledByUserInput
      let result = session.cancel(reason)
      apply(result.commands, currentEvent: nil)
      releasePendingSecondaryTrigger()
      lifecycleLock.lock()
      shortcutCaptureState.releaseSuppressedKeys()
      triggerButtonCaptureState.releaseSuppressedButton()
      lifecycleLock.unlock()
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    if handleTriggerButtonRecordingEvent(type: type, event: event) {
      return nil
    }

    guard
      let triggerEvent = triggerEvent(type: type, event: event)
    else {
      return Unmanaged.passUnretained(event)
    }
    return processTriggerEvent(
      phase: triggerEvent.phase,
      triggerButton: triggerEvent.button,
      event: event
    )
  }

  private func processTriggerEvent(
    phase: TriggerEventPhase,
    triggerButton: GestureTriggerButton,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    let inputDevice: GestureInputDevice =
      triggerButton == .trackpad
      ? .trackpad
      : .mouse(identifier: nil)
    let shouldResolveWindowUnderPointer =
      phase == .down
      && triggerButton.keyboardKeyCode == nil
      && triggerButton != .trackpad
    let bundleID = frontmostAppProvider.currentBundleID(
      at: shouldResolveWindowUnderPointer ? event.location : nil
    )

    if triggerButton == inputConfiguration.secondaryTriggerButton {
      return handleSecondaryTriggerEvent(
        phase: phase,
        event: event,
        bundleID: bundleID
      )
    }

    if phase == .up,
      activeTriggerButton == triggerButton,
      let request = pendingRepeatRequest
    {
      pendingRepeatRequest = nil
      let usesSecondaryTrigger =
        activeSessionUsesSecondaryTrigger
      abandonSessionForRepeatedAction()
      repeatState = RepeatState(
        request: request,
        triggerButton: triggerButton,
        bundleID: bundleID,
        usesSecondaryTrigger: usesSecondaryTrigger,
        expiresAt: ProcessInfo.processInfo.systemUptime + 2
      )
      dispatchAction(request)
      return nil
    }

    if phase == .dragged, pendingRepeatRequest != nil {
      pendingRepeatRequest = nil
      repeatState = nil
    }

    if phase == .up {
      if suppressedMouseUpButtons.remove(triggerButton) != nil {
        return nil
      }
    }

    if phase == .down {
      if activeTriggerButton == triggerButton {
        return nil
      }
      if let state = repeatState {
        let now = ProcessInfo.processInfo.systemUptime
        if now <= state.expiresAt,
          state.triggerButton == triggerButton,
          state.bundleID == bundleID
        {
          if state.usesSecondaryTrigger == secondaryTriggerIsDown {
            pendingRepeatRequest = state.request
          } else if !state.usesSecondaryTrigger {
            repeatState = nil
          }
        } else {
          repeatState = nil
        }
      }
      if activeTriggerButton != nil {
        return Unmanaged.passUnretained(event)
      }
    }

    if phase != .down,
      activeTriggerButton != triggerButton
    {
      return Unmanaged.passUnretained(event)
    }

    let sourceUserData = event.getIntegerValueField(
      .eventSourceUserData
    )
    let point = GesturePoint(
      x: Float(event.location.x),
      y: Float(event.location.y)
    )
    let timestamp = TimeInterval(event.timestamp) / 1_000_000_000
    let result: GestureSessionResult

    switch phase {
    case .down:
      result = session.mouseDown(
        at: point,
        timestamp: timestamp,
        frontmostBundleID: bundleID,
        shouldTrack: isEnabled
          && !isExcluded(
            bundleID: bundleID,
            triggerButton: triggerButton
          )
          && mappingSnapshot.hasApplicableMapping(
            for: bundleID,
            triggerButton: triggerButton,
            default: inputConfiguration.triggerButton,
            inputDevice: inputDevice
          ),
        triggerButton: triggerButton,
        sourceUserData: sourceUserData
      )
      if result.disposition == .suppress {
        guard let copy = event.copy() else {
          let failure = session.cancel(.configurationInvalid, at: point)
          apply(failure.commands, currentEvent: nil)
          return Unmanaged.passUnretained(event)
        }
        pendingMouseDown = copy
        activeTriggerButton = triggerButton
        if secondaryTriggerIsDown {
          activeSessionUsesSecondaryTrigger = true
          pendingSecondaryMouseDown = nil
          secondaryTriggerIsPassingThrough = false
          if let secondaryButton =
            inputConfiguration.secondaryTriggerButton
          {
            suppressedMouseUpButtons.insert(secondaryButton)
          }
        }
        beginSessionSignpost()
      }
    case .dragged:
      result = session.mouseDragged(
        to: point,
        timestamp: timestamp,
        sourceUserData: sourceUserData
      )
    case .up:
      result = session.mouseUp(
        at: point,
        timestamp: timestamp,
        sourceUserData: sourceUserData
      )
    }

    apply(result.commands, currentEvent: event)
    if phase == .dragged, triggerButton.keyboardKeyCode != nil {
      return Unmanaged.passUnretained(event)
    }
    return result.disposition == .passThrough
      ? Unmanaged.passUnretained(event)
      : nil
  }

  private func handleShortcutEvent(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    let sourceUserData = event.getIntegerValueField(
      .eventSourceUserData
    )
    guard !EventSourceMarker.isSynthetic(sourceUserData) else {
      return Unmanaged.passUnretained(event)
    }

    if handleTriggerButtonRecordingEvent(type: type, event: event) {
      return nil
    }

    let keyCode = UInt16(
      event.getIntegerValueField(.keyboardEventKeycode)
    )
    if handleEscape(
      type: type,
      keyCode: keyCode
    ) {
      return nil
    }

    let result: ShortcutCaptureResult
    var handler: ShortcutRecordingHandler?
    var toggleHandler: GlobalToggleHandler?
    var didSuppressGlobalToggle = false

    lifecycleLock.lock()
    switch type {
    case .keyDown:
      result = shortcutCaptureState.handleKeyDown(
        keyCode: keyCode,
        modifiers: event.flags.rawValue
      )
      if case .captured = result {
        handler = shortcutRecording?.handler
        shortcutRecording = nil
      }
    case .keyUp:
      result = shortcutCaptureState.handleKeyUp(keyCode: keyCode)
    default:
      result = .passThrough
    }
    if result == .passThrough {
      switch type {
      case .keyDown:
        let modifiers =
          ShortcutRecordingSession.normalizedModifiers(
            event.flags.rawValue
          )
        if keyCode == globalToggleShortcut.keyCode,
          modifiers == globalToggleShortcut.modifiers
        {
          isSuppressingGlobalToggle = true
          toggleHandler = globalToggleHandler
          didSuppressGlobalToggle = true
        }
      case .keyUp:
        if isSuppressingGlobalToggle,
          keyCode == globalToggleShortcut.keyCode
        {
          isSuppressingGlobalToggle = false
          didSuppressGlobalToggle = true
        }
      default:
        break
      }
    }
    lifecycleLock.unlock()

    if case .captured(let keyCode, let modifiers) = result {
      handler?(keyCode, modifiers)
    }
    toggleHandler?()
    if didSuppressGlobalToggle {
      return nil
    }
    guard result == .passThrough else {
      return nil
    }
    if let triggerEvent = keyboardTriggerEvent(
      type: type,
      keyCode: keyCode
    ) {
      return processTriggerEvent(
        phase: triggerEvent.phase,
        triggerButton: triggerEvent.button,
        event: event
      )
    }
    return Unmanaged.passUnretained(event)
  }

  private func handleEscape(
    type: CGEventType,
    keyCode: UInt16
  ) -> Bool {
    guard keyCode == 53 else { return false }
    if type == .keyUp, isSuppressingEscape {
      isSuppressingEscape = false
      return true
    }
    guard type == .keyDown else {
      return false
    }
    lifecycleLock.lock()
    let isRecording = shortcutRecording != nil
    lifecycleLock.unlock()
    guard !isRecording else { return false }

    if session.state != .idle {
      if let activeTriggerButton {
        suppressedMouseUpButtons.insert(activeTriggerButton)
      }
      if activeSessionUsesSecondaryTrigger,
        let secondaryButton = inputConfiguration.secondaryTriggerButton
      {
        suppressedMouseUpButtons.insert(secondaryButton)
      }
      isSuppressingEscape = true
      let result = session.abandon()
      apply(result.commands, currentEvent: nil)
      pendingMouseDown = nil
      activeTriggerButton = nil
      activeSessionUsesSecondaryTrigger = false
      pendingRepeatRequest = nil
      repeatState = nil
      endSessionSignpost()
      feedbackSink.show(.cancelled)
      return true
    }
    if repeatState != nil {
      repeatState = nil
      pendingRepeatRequest = nil
      isSuppressingEscape = true
      feedbackSink.show(.cancelled)
      return true
    }
    return false
  }

  private func handleTriggerButtonRecordingEvent(
    type: CGEventType,
    event: CGEvent
  ) -> Bool {
    guard
      !EventSourceMarker.isSynthetic(
        event.getIntegerValueField(.eventSourceUserData)
      )
    else {
      return false
    }
    let result: TriggerButtonCaptureResult
    var handler: TriggerButtonRecordingHandler?

    lifecycleLock.lock()
    switch type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      result = triggerButtonCaptureState.handleMouseDown(
        buttonNumber: event.getIntegerValueField(
          .mouseEventButtonNumber
        )
      )
      if case .captured = result {
        handler = triggerButtonRecording?.handler
        triggerButtonRecording = nil
      }
    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      result = triggerButtonCaptureState.handleMouseDragged(
        buttonNumber: event.getIntegerValueField(
          .mouseEventButtonNumber
        )
      )
    case .leftMouseUp, .rightMouseUp, .otherMouseUp:
      result = triggerButtonCaptureState.handleMouseUp(
        buttonNumber: event.getIntegerValueField(
          .mouseEventButtonNumber
        )
      )
    case .keyDown:
      result = triggerButtonCaptureState.handleKeyDown(
        keyCode: UInt16(
          event.getIntegerValueField(.keyboardEventKeycode)
        )
      )
      if case .captured = result {
        handler = triggerButtonRecording?.handler
        triggerButtonRecording = nil
      }
    case .keyUp:
      result = triggerButtonCaptureState.handleKeyUp(
        keyCode: UInt16(
          event.getIntegerValueField(.keyboardEventKeycode)
        )
      )
    default:
      result = .passThrough
    }
    lifecycleLock.unlock()

    if case .captured(let triggerButton) = result {
      handler?(triggerButton)
    }
    return result != .passThrough
  }

  private func apply(
    _ commands: [GestureSessionCommand],
    currentEvent: CGEvent?
  ) {
    if commands.contains(where: {
      if case .didFailOpen = $0 {
        return true
      }
      return false
    }), let activeTriggerButton {
      suppressedMouseUpButtons.insert(activeTriggerButton)
    }
    for command in commands {
      switch command {
      case .showOverlay(let point):
        overlaySink.show(at: point)
      case .appendOverlayPoint(let point):
        overlaySink.append(point)
      case .hideOverlay:
        overlaySink.hide()
      case .replayPendingClick(let location):
        replayClick(
          mouseUpLocation: location,
          currentEvent: currentEvent
        )
        activeTriggerButton = nil
        activeSessionUsesSecondaryTrigger = false
        endSessionSignpost()
      case .recognize(let candidate):
        let recognizedCandidate = candidate.usingSecondaryTrigger(
          activeSessionUsesSecondaryTrigger
        )
        pendingMouseDown = nil
        activeTriggerButton = nil
        activeSessionUsesSecondaryTrigger = false
        endSessionSignpost()
        enqueueRecognition(recognizedCandidate)
      case .didFailOpen:
        feedbackSink.show(.cancelled)
        activeTriggerButton = nil
        activeSessionUsesSecondaryTrigger = false
        endSessionSignpost()
      }
    }
  }

  private func replayClick(
    mouseUpLocation: GesturePoint,
    currentEvent: CGEvent?
  ) {
    guard let mouseDown = pendingMouseDown else { return }
    pendingMouseDown = nil

    let triggerButton =
      activeTriggerButton ?? inputConfiguration.triggerButton
    let triggerUp: CGEvent?
    if let keyboardKeyCode = triggerButton.keyboardKeyCode {
      if let currentEvent, currentEvent.type == .keyUp {
        triggerUp = currentEvent.copy()
      } else {
        triggerUp = CGEvent(
          keyboardEventSource: nil,
          virtualKey: CGKeyCode(keyboardKeyCode),
          keyDown: false
        )
      }
    } else if let currentEvent,
      triggerEvent(
        type: currentEvent.type,
        event: currentEvent
      )?.phase == .up
    {
      triggerUp = currentEvent.copy()
    } else {
      triggerUp = CGEvent(
        mouseEventSource: nil,
        mouseType: triggerButton.mouseUpEventType,
        mouseCursorPosition: CGPoint(
          x: CGFloat(mouseUpLocation.x),
          y: CGFloat(mouseUpLocation.y)
        ),
        mouseButton:
          CGMouseButton(
            rawValue: triggerButton.buttonNumber
          ) ?? .right
      )
    }

    guard let replayDown = mouseDown.copy(),
      let replayUp = triggerUp
    else {
      return
    }
    for replayEvent in [replayDown, replayUp] {
      replayEvent.setIntegerValueField(
        .eventSourceUserData,
        value: EventSourceMarker.syntheticEventUserData
      )
      replayEvent.post(tap: .cgSessionEventTap)
    }
  }

  private func enqueueRecognition(_ candidate: GestureCandidate) {
    guard let runLoop else { return }
    let snapshot = mappingSnapshot
    CFRunLoopPerformBlock(
      runLoop,
      CFRunLoopMode.defaultMode!.rawValue as CFTypeRef
    ) { [self] in
      let signpostID = OSSignpostID(log: Self.performanceLog)
      os_signpost(
        .begin,
        log: Self.performanceLog,
        name: "GestureProcessing",
        signpostID: signpostID
      )
      defer {
        os_signpost(
          .end,
          log: Self.performanceLog,
          name: "GestureProcessing",
          signpostID: signpostID
        )
      }

      let normalizationID = OSSignpostID(log: Self.performanceLog)
      os_signpost(
        .begin,
        log: Self.performanceLog,
        name: "Normalization",
        signpostID: normalizationID
      )
      let gesture = try? normalizer.normalize(candidate.points)
      os_signpost(
        .end,
        log: Self.performanceLog,
        name: "Normalization",
        signpostID: normalizationID
      )
      guard let gesture else {
        feedbackSink.show(.noMatch)
        return
      }

      let recognitionID = OSSignpostID(log: Self.performanceLog)
      os_signpost(
        .begin,
        log: Self.performanceLog,
        name: "Recognition",
        signpostID: recognitionID
      )
      let decision = recognizer.recognize(
        gesture,
        mappings: snapshot.mappings(
          for: candidate.triggerButton,
          default: inputConfiguration.triggerButton
        ),
        frontmostBundleID: candidate.frontmostBundleID,
        inputDevice: candidate.inputDevice,
        useSecondaryAction: candidate.usesSecondaryTrigger
      )
      os_signpost(
        .end,
        log: Self.performanceLog,
        name: "Recognition",
        signpostID: recognitionID
      )
      switch decision {
      case .noMatch:
        feedbackSink.show(.noMatch)
        return
      case .ambiguous:
        feedbackSink.show(.ambiguous)
        return
      case .matched:
        break
      }
      guard case .matched(let match) = decision else { return }
      repeatState =
        match.request.repeatModeEnabled
        ? RepeatState(
          request: match.request,
          triggerButton: candidate.triggerButton,
          bundleID: candidate.frontmostBundleID,
          usesSecondaryTrigger: candidate.usesSecondaryTrigger,
          expiresAt: ProcessInfo.processInfo.systemUptime + 2
        )
        : nil

      let actionID = OSSignpostID(log: Self.performanceLog)
      os_signpost(
        .begin,
        log: Self.performanceLog,
        name: "ActionDispatch",
        signpostID: actionID
      )
      Task { [actionDispatcher] in
        await actionDispatcher.submit(match.request)
      }
      os_signpost(
        .end,
        log: Self.performanceLog,
        name: "ActionDispatch",
        signpostID: actionID
      )
    }
    CFRunLoopWakeUp(runLoop)
  }

  private func abandonSessionForRepeatedAction() {
    if activeSessionUsesSecondaryTrigger,
      let secondaryButton = inputConfiguration.secondaryTriggerButton
    {
      suppressedMouseUpButtons.insert(secondaryButton)
    }
    let result = session.abandon()
    apply(result.commands, currentEvent: nil)
    pendingMouseDown = nil
    pendingRepeatRequest = nil
    repeatState = nil
    activeTriggerButton = nil
    activeSessionUsesSecondaryTrigger = false
    endSessionSignpost()
  }

  private func handleSecondaryTriggerEvent(
    phase: TriggerEventPhase,
    event: CGEvent,
    bundleID: String?
  ) -> Unmanaged<CGEvent>? {
    let sourceUserData = event.getIntegerValueField(
      .eventSourceUserData
    )
    guard !EventSourceMarker.isSynthetic(sourceUserData) else {
      return Unmanaged.passUnretained(event)
    }

    switch phase {
    case .down:
      if secondaryTriggerIsDown {
        return nil
      }
      secondaryTriggerIsDown = true
      if activeTriggerButton != nil {
        activeSessionUsesSecondaryTrigger = true
        if let state = repeatState,
          state.usesSecondaryTrigger,
          state.triggerButton == activeTriggerButton,
          state.bundleID == bundleID,
          ProcessInfo.processInfo.systemUptime <= state.expiresAt
        {
          pendingRepeatRequest = state.request
        } else {
          pendingRepeatRequest = nil
          repeatState = nil
        }
        if let secondaryButton =
          inputConfiguration.secondaryTriggerButton
        {
          suppressedMouseUpButtons.insert(secondaryButton)
        }
        return nil
      }
      guard
        isEnabled,
        !isExcluded(
          bundleID: bundleID,
          triggerButton:
            inputConfiguration.secondaryTriggerButton ?? .right
        ),
        mappingSnapshot.hasApplicableSecondaryAction(
          for: bundleID
        ),
        let copy = event.copy()
      else {
        secondaryTriggerIsDown = false
        return Unmanaged.passUnretained(event)
      }
      pendingSecondaryMouseDown = copy
      secondaryTriggerIsPassingThrough = false
      return nil
    case .dragged:
      if activeTriggerButton != nil,
        activeSessionUsesSecondaryTrigger
      {
        let point = GesturePoint(
          x: Float(event.location.x),
          y: Float(event.location.y)
        )
        let timestamp =
          TimeInterval(event.timestamp) / 1_000_000_000
        let result = session.mouseDragged(
          to: point,
          timestamp: timestamp,
          sourceUserData: sourceUserData
        )
        apply(result.commands, currentEvent: event)
        return result.disposition == .passThrough
          ? Unmanaged.passUnretained(event)
          : nil
      }
      if pendingSecondaryMouseDown != nil {
        replayPendingSecondaryMouseDown()
        secondaryTriggerIsPassingThrough = true
      }
      return Unmanaged.passUnretained(event)
    case .up:
      secondaryTriggerIsDown = false
      if secondaryTriggerIsPassingThrough {
        secondaryTriggerIsPassingThrough = false
        return Unmanaged.passUnretained(event)
      }
      if let secondaryButton =
        inputConfiguration.secondaryTriggerButton,
        suppressedMouseUpButtons.remove(secondaryButton) != nil
      {
        pendingSecondaryMouseDown = nil
        return nil
      }
      if pendingSecondaryMouseDown != nil {
        replaySecondaryClick(mouseUpEvent: event)
        return nil
      }
      if activeSessionUsesSecondaryTrigger {
        return nil
      }
      return Unmanaged.passUnretained(event)
    }
  }

  private func replayPendingSecondaryMouseDown() {
    guard let mouseDown = pendingSecondaryMouseDown else { return }
    pendingSecondaryMouseDown = nil
    guard let replayDown = mouseDown.copy() else { return }
    replayDown.setIntegerValueField(
      .eventSourceUserData,
      value: EventSourceMarker.syntheticEventUserData
    )
    replayDown.post(tap: .cgSessionEventTap)
  }

  private func replaySecondaryClick(mouseUpEvent: CGEvent) {
    guard let mouseDown = pendingSecondaryMouseDown else { return }
    pendingSecondaryMouseDown = nil
    guard
      let replayDown = mouseDown.copy(),
      let replayUp = mouseUpEvent.copy()
    else {
      return
    }
    for replayEvent in [replayDown, replayUp] {
      replayEvent.setIntegerValueField(
        .eventSourceUserData,
        value: EventSourceMarker.syntheticEventUserData
      )
      replayEvent.post(tap: .cgSessionEventTap)
    }
  }

  private func releasePendingSecondaryTrigger() {
    if pendingSecondaryMouseDown != nil {
      replayPendingSecondaryMouseDown()
    }
    secondaryTriggerIsDown = false
    secondaryTriggerIsPassingThrough = false
    activeSessionUsesSecondaryTrigger = false
  }

  private func dispatchAction(_ request: ActionRequest) {
    Task { [actionDispatcher] in
      await actionDispatcher.submit(request)
    }
  }

  private func beginSessionSignpost() {
    guard activeSessionSignpostID == nil else { return }
    let signpostID = OSSignpostID(log: Self.performanceLog)
    activeSessionSignpostID = signpostID
    os_signpost(
      .begin,
      log: Self.performanceLog,
      name: "GestureSession",
      signpostID: signpostID
    )
  }

  private func endSessionSignpost() {
    guard let signpostID = activeSessionSignpostID else { return }
    activeSessionSignpostID = nil
    os_signpost(
      .end,
      log: Self.performanceLog,
      name: "GestureSession",
      signpostID: signpostID
    )
  }

  private func notifyState(_ state: EventTapManagerState) {
    lifecycleLock.lock()
    let handler = stateHandler
    lifecycleLock.unlock()
    handler?(state)
  }

  private func triggerEvent(
    type: CGEventType,
    event: CGEvent
  ) -> (button: GestureTriggerButton, phase: TriggerEventPhase)? {
    if type == .mouseMoved,
      let activeTriggerButton,
      activeTriggerButton.keyboardKeyCode != nil
    {
      return (activeTriggerButton, .dragged)
    }

    let number = event.getIntegerValueField(
      .mouseEventButtonNumber
    )
    guard number >= 0, UInt64(number) <= UInt64(UInt32.max) else {
      return nil
    }
    let normalizedModifiers =
      ShortcutRecordingSession.normalizedModifiers(
        event.flags.rawValue
      )
    let isTrackpadTrigger =
      inputConfiguration.isTrackpadGestureEnabled
      && number == 0
      && (normalizedModifiers == inputConfiguration.trackpadModifiers
        || (activeTriggerButton == .trackpad
          && type != .leftMouseDown))
    let button =
      isTrackpadTrigger
      ? GestureTriggerButton.trackpad
      : GestureTriggerButton(buttonNumber: UInt32(number))
    guard
      let phase = button.eventPhase(
        for: type,
        buttonNumber: number
      )
    else {
      return nil
    }
    return (button, phase)
  }

  private func keyboardTriggerEvent(
    type: CGEventType,
    keyCode: UInt16
  ) -> (button: GestureTriggerButton, phase: TriggerEventPhase)? {
    let button = GestureTriggerButton.keyboard(keyCode: keyCode)
    guard
      button == inputConfiguration.triggerButton
        || button == inputConfiguration.secondaryTriggerButton
    else {
      return nil
    }
    switch type {
    case .keyDown:
      return (button, .down)
    case .keyUp:
      return (button, .up)
    default:
      return nil
    }
  }

  private func isExcluded(
    bundleID: String?,
    triggerButton: GestureTriggerButton
  ) -> Bool {
    guard let bundleID else { return false }
    return exclusionRules.contains {
      $0.bundleIdentifier == bundleID
        && ($0.triggerButton == nil
          || $0.triggerButton == triggerButton)
    }
  }

  private static let eventMask: CGEventMask = [
    CGEventType.leftMouseDown,
    .leftMouseDragged,
    .leftMouseUp,
    CGEventType.rightMouseDown,
    .rightMouseDragged,
    .rightMouseUp,
    .otherMouseDown,
    .otherMouseDragged,
    .otherMouseUp,
    .mouseMoved,
    .keyDown,
    .keyUp,
  ].reduce(0) { mask, type in
    mask | (1 << type.rawValue)
  }
}

private struct RepeatState {
  let request: ActionRequest
  let triggerButton: GestureTriggerButton
  let bundleID: String?
  let usesSecondaryTrigger: Bool
  let expiresAt: TimeInterval
}

enum TriggerEventPhase: Equatable {
  case down
  case dragged
  case up
}

extension GestureTriggerButton {
  fileprivate var mouseUpEventType: CGEventType {
    if self == .trackpad {
      return .leftMouseUp
    }
    return switch buttonNumber {
    case 0:
      .leftMouseUp
    case 1:
      .rightMouseUp
    default:
      .otherMouseUp
    }
  }

  func eventPhase(
    for type: CGEventType,
    buttonNumber eventButtonNumber: Int64
  ) -> TriggerEventPhase? {
    guard keyboardKeyCode == nil else {
      return nil
    }
    if self == .trackpad {
      switch type {
      case .leftMouseDown:
        return .down
      case .leftMouseDragged:
        return .dragged
      case .leftMouseUp:
        return .up
      default:
        return nil
      }
    }
    switch buttonNumber {
    case 0:
      switch type {
      case .leftMouseDown:
        return .down
      case .leftMouseDragged:
        return .dragged
      case .leftMouseUp:
        return .up
      default:
        return nil
      }
    case 1:
      switch type {
      case .rightMouseDown:
        return .down
      case .rightMouseDragged:
        return .dragged
      case .rightMouseUp:
        return .up
      default:
        return nil
      }
    default:
      guard eventButtonNumber == Int64(buttonNumber) else {
        return nil
      }
      switch type {
      case .otherMouseDown:
        return .down
      case .otherMouseDragged:
        return .dragged
      case .otherMouseUp:
        return .up
      default:
        return nil
      }
    }
  }
}

enum TriggerButtonCaptureResult: Equatable {
  case passThrough
  case suppress
  case captured(GestureTriggerButton)
}

struct TriggerButtonCaptureState {
  private(set) var isRecording = false
  private var suppressedButtonNumber: Int64?
  private var suppressedKeyCode: UInt16?

  mutating func begin() {
    isRecording = true
  }

  mutating func cancel() {
    isRecording = false
  }

  mutating func releaseSuppressedButton() {
    suppressedButtonNumber = nil
    suppressedKeyCode = nil
  }

  mutating func reset() {
    isRecording = false
    releaseSuppressedButton()
  }

  mutating func handleMouseDown(
    buttonNumber: Int64
  ) -> TriggerButtonCaptureResult {
    if suppressedButtonNumber == buttonNumber {
      return .suppress
    }
    guard
      isRecording,
      buttonNumber >= 0,
      UInt64(buttonNumber) <= UInt64(UInt32.max)
    else {
      return .passThrough
    }

    isRecording = false
    suppressedButtonNumber = buttonNumber
    return .captured(
      GestureTriggerButton(buttonNumber: UInt32(buttonNumber))
    )
  }

  mutating func handleMouseDragged(
    buttonNumber: Int64
  ) -> TriggerButtonCaptureResult {
    suppressedButtonNumber == buttonNumber
      ? .suppress
      : .passThrough
  }

  mutating func handleMouseUp(
    buttonNumber: Int64
  ) -> TriggerButtonCaptureResult {
    guard suppressedButtonNumber == buttonNumber else {
      return .passThrough
    }
    suppressedButtonNumber = nil
    return .suppress
  }

  mutating func handleKeyDown(
    keyCode: UInt16
  ) -> TriggerButtonCaptureResult {
    if suppressedKeyCode == keyCode {
      return .suppress
    }
    guard isRecording, keyCode != 53 else {
      return .passThrough
    }

    isRecording = false
    suppressedKeyCode = keyCode
    return .captured(.keyboard(keyCode: keyCode))
  }

  mutating func handleKeyUp(
    keyCode: UInt16
  ) -> TriggerButtonCaptureResult {
    guard suppressedKeyCode == keyCode else {
      return .passThrough
    }
    suppressedKeyCode = nil
    return .suppress
  }
}

private func eventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else {
    return Unmanaged.passUnretained(event)
  }
  let manager = Unmanaged<EventTapManager>
    .fromOpaque(userInfo)
    .takeUnretainedValue()
  return manager.handle(type: type, event: event)
}
