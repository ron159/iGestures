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

  private let lifecycleLock = NSLock()
  private static let performanceLog = OSLog(
    subsystem: "com.ron159.igestures",
    category: "Performance"
  )
  private let frontmostAppProvider: any FrontmostAppProviding
  private let shortcutExecutor: any ShortcutExecuting
  private let overlaySink: any GestureOverlaySinking
  private let normalizer: GestureNormalizer
  private let recognizer: GestureRecognizer

  private var thread: Thread?
  private var runLoop: CFRunLoop?
  private var pendingSnapshot = CompiledMappingSnapshot.empty
  private var pendingEnabled = false
  private var pendingInputConfiguration =
    GestureInputConfiguration.default
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

  // The following properties are confined to the Event Tap thread.
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var session = GestureSession()
  private var pendingMouseDown: CGEvent?
  private var mappingSnapshot = CompiledMappingSnapshot.empty
  private var isEnabled = false
  private var inputConfiguration = GestureInputConfiguration.default
  private var activeSessionSignpostID: OSSignpostID?

  public init(
    frontmostAppProvider: any FrontmostAppProviding =
      SystemFrontmostAppProvider(),
    shortcutExecutor: any ShortcutExecuting = SystemShortcutExecutor(),
    overlaySink: any GestureOverlaySinking = NoOpGestureOverlaySink(),
    normalizer: GestureNormalizer = GestureNormalizer(),
    recognizer: GestureRecognizer = GestureRecognizer()
  ) {
    self.frontmostAppProvider = frontmostAppProvider
    self.shortcutExecutor = shortcutExecutor
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
      inputConfiguration = configuration
      session = GestureSession(
        configuration: .init(
          minimumTriggerDuration: configuration.triggerDuration
        )
      )
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

    guard let phase = triggerEventPhase(type: type, event: event) else {
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
      let bundleID = frontmostAppProvider.currentBundleID()
      result = session.mouseDown(
        at: point,
        timestamp: timestamp,
        frontmostBundleID: bundleID,
        shouldTrack: isEnabled
          && mappingSnapshot.hasApplicableMapping(for: bundleID),
        sourceUserData: sourceUserData
      )
      if result.disposition == .suppress {
        guard let copy = event.copy() else {
          let failure = session.cancel(.configurationInvalid, at: point)
          apply(failure.commands, currentEvent: nil)
          return Unmanaged.passUnretained(event)
        }
        pendingMouseDown = copy
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

    let keyCode = UInt16(
      event.getIntegerValueField(.keyboardEventKeycode)
    )
    let result: ShortcutCaptureResult
    var handler: ShortcutRecordingHandler?

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
    lifecycleLock.unlock()

    if case .captured(let keyCode, let modifiers) = result {
      handler?(keyCode, modifiers)
    }
    return result == .passThrough
      ? Unmanaged.passUnretained(event)
      : nil
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
    let buttonNumber = event.getIntegerValueField(
      .mouseEventButtonNumber
    )
    let result: TriggerButtonCaptureResult
    var handler: TriggerButtonRecordingHandler?

    lifecycleLock.lock()
    switch type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      result = triggerButtonCaptureState.handleMouseDown(
        buttonNumber: buttonNumber
      )
      if case .captured = result {
        handler = triggerButtonRecording?.handler
        triggerButtonRecording = nil
      }
    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      result = triggerButtonCaptureState.handleMouseDragged(
        buttonNumber: buttonNumber
      )
    case .leftMouseUp, .rightMouseUp, .otherMouseUp:
      result = triggerButtonCaptureState.handleMouseUp(
        buttonNumber: buttonNumber
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
        endSessionSignpost()
      case .recognize(let candidate):
        pendingMouseDown = nil
        endSessionSignpost()
        enqueueRecognition(candidate)
      case .didFailOpen:
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

    let mouseUp: CGEvent?
    if let currentEvent,
      triggerEventPhase(
        type: currentEvent.type,
        event: currentEvent
      ) == .up
    {
      mouseUp = currentEvent.copy()
    } else {
      let triggerButton = inputConfiguration.triggerButton
      mouseUp = CGEvent(
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
      let replayUp = mouseUp
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
      guard let gesture else { return }

      let recognitionID = OSSignpostID(log: Self.performanceLog)
      os_signpost(
        .begin,
        log: Self.performanceLog,
        name: "Recognition",
        signpostID: recognitionID
      )
      let decision = recognizer.recognize(
        gesture,
        mappings: snapshot.mappings,
        frontmostBundleID: candidate.frontmostBundleID
      )
      os_signpost(
        .end,
        log: Self.performanceLog,
        name: "Recognition",
        signpostID: recognitionID
      )
      guard case .matched(let match) = decision else { return }

      let shortcutID = OSSignpostID(log: Self.performanceLog)
      os_signpost(
        .begin,
        log: Self.performanceLog,
        name: "ShortcutPost",
        signpostID: shortcutID
      )
      _ = shortcutExecutor.execute(match.shortcut)
      os_signpost(
        .end,
        log: Self.performanceLog,
        name: "ShortcutPost",
        signpostID: shortcutID
      )
    }
    CFRunLoopWakeUp(runLoop)
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

  private func triggerEventPhase(
    type: CGEventType,
    event: CGEvent
  ) -> TriggerEventPhase? {
    inputConfiguration.triggerButton.eventPhase(
      for: type,
      buttonNumber: event.getIntegerValueField(
        .mouseEventButtonNumber
      )
    )
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
    .keyDown,
    .keyUp,
  ].reduce(0) { mask, type in
    mask | (1 << type.rawValue)
  }
}

enum TriggerEventPhase: Equatable {
  case down
  case dragged
  case up
}

extension GestureTriggerButton {
  fileprivate var mouseUpEventType: CGEventType {
    switch buttonNumber {
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

  mutating func begin() {
    isRecording = true
  }

  mutating func cancel() {
    isRecording = false
  }

  mutating func releaseSuppressedButton() {
    suppressedButtonNumber = nil
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
