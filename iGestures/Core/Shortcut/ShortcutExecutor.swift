import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

public struct KeyboardEventDescriptor: Equatable, Sendable {
  public let keyCode: UInt16
  public let modifiers: UInt64
  public let isKeyDown: Bool
  public let sourceUserData: Int64

  public init(
    keyCode: UInt16,
    modifiers: UInt64,
    isKeyDown: Bool,
    sourceUserData: Int64
  ) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.isKeyDown = isKeyDown
    self.sourceUserData = sourceUserData
  }
}

public protocol ShortcutExecuting: Sendable {
  @discardableResult
  func execute(_ shortcut: KeyboardShortcut) -> Bool
}

public struct SystemShortcutExecutor: ShortcutExecuting {
  public init() {}

  public static func eventSequence(
    for shortcut: KeyboardShortcut
  ) -> [KeyboardEventDescriptor] {
    guard shortcut.isValid else { return [] }
    return [true, false].map {
      KeyboardEventDescriptor(
        keyCode: shortcut.keyCode,
        modifiers: shortcut.modifiers,
        isKeyDown: $0,
        sourceUserData: EventSourceMarker.syntheticEventUserData
      )
    }
  }

  @discardableResult
  public func execute(_ shortcut: KeyboardShortcut) -> Bool {
    let descriptors = Self.eventSequence(for: shortcut)
    guard descriptors.count == 2,
      let source = CGEventSource(stateID: .hidSystemState),
      let events = createEvents(descriptors, source: source)
    else {
      return false
    }

    for (event, descriptor) in zip(events, descriptors) {
      event.setIntegerValueField(
        .eventSourceUserData,
        value: descriptor.sourceUserData
      )
      event.post(tap: .cgSessionEventTap)
    }
    return true
  }

  private func createEvents(
    _ descriptors: [KeyboardEventDescriptor],
    source: CGEventSource
  ) -> [CGEvent]? {
    var events: [CGEvent] = []
    events.reserveCapacity(descriptors.count)

    for descriptor in descriptors {
      guard
        let event = CGEvent(
          keyboardEventSource: source,
          virtualKey: CGKeyCode(descriptor.keyCode),
          keyDown: descriptor.isKeyDown
        )
      else {
        return nil
      }
      event.flags = CGEventFlags(rawValue: descriptor.modifiers)
      events.append(event)
    }
    return events
  }
}

public enum ActionExecutionFailure: Equatable, Sendable {
  case invalidAction
  case targetNotFound
  case launchFailed
  case processFailed(exitCode: Int32)
  case timedOut
  case outputLimitExceeded
  case notConfirmed
}

public enum ActionExecutionResult: Equatable, Sendable {
  case succeeded
  case failed(ActionExecutionFailure)
}

public protocol ActionExecuting: Sendable {
  func execute(_ request: ActionRequest) async -> ActionExecutionResult
}

public typealias ScriptExecutionAuthorizer =
  @MainActor @Sendable (AutomationScript) -> Bool

public struct SystemGestureActionExecutor: ActionExecuting {
  private let shortcutExecutor: any ShortcutExecuting
  private let scriptExecutionAuthorizer: ScriptExecutionAuthorizer

  public init(
    shortcutExecutor: any ShortcutExecuting = SystemShortcutExecutor(),
    scriptExecutionAuthorizer:
      @escaping ScriptExecutionAuthorizer = { _ in true }
  ) {
    self.shortcutExecutor = shortcutExecutor
    self.scriptExecutionAuthorizer = scriptExecutionAuthorizer
  }

  public func execute(
    _ request: ActionRequest
  ) async -> ActionExecutionResult {
    await execute(
      request.action,
      request: request,
      depth: 0
    )
  }

  private func execute(
    _ action: GestureAction,
    request: ActionRequest,
    depth: Int
  ) async -> ActionExecutionResult {
    guard depth <= 20 else {
      return .failed(.invalidAction)
    }

    switch action {
    case .none:
      return .succeeded
    case .keyboardShortcut(let shortcut):
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      return shortcutExecutor.execute(shortcut)
        ? .succeeded
        : .failed(.launchFailed)
    case .openURL(let value):
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      guard let url = URL(string: value) else {
        return .failed(.invalidAction)
      }
      return NSWorkspace.shared.open(url)
        ? .succeeded
        : .failed(.launchFailed)
    case .openPath(let value):
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      let path = NSString(string: value).expandingTildeInPath
      return NSWorkspace.shared.open(
        URL(fileURLWithPath: path)
      )
        ? .succeeded
        : .failed(.launchFailed)
    case .launchApplication(let bundleIdentifier):
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      return await launchApplication(
        bundleIdentifier: bundleIdentifier
      )
    case .system(let action):
      return await executeSystemAction(action)
    case .window(let action):
      return await MainActor.run {
        WindowGestureActionExecutor.execute(action)
      }
    case .customWindow(let frame):
      return await MainActor.run {
        WindowGestureActionExecutor.execute(frame)
      }
    case .typeText(let text):
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      return await MainActor.run {
        SyntheticTextInputExecutor.execute(text)
      }
        ? .succeeded
        : .failed(.launchFailed)
    case .applicationMenu(let menuAction):
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      return await MainActor.run {
        ApplicationMenuActionExecutor.execute(menuAction)
      }
    case .appleShortcut(let name):
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      return await runProcess(
        executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
        arguments: ["run", name]
      )
    case .sequence(let sequence):
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      for step in sequence.steps {
        let result = await execute(
          step.action,
          request: request,
          depth: depth + 1
        )
        if result != .succeeded {
          switch sequence.failurePolicy {
          case .stop:
            return result
          case .continue:
            break
          case .fallback(let fallback):
            return await execute(
              fallback,
              request: request,
              depth: depth + 1
            )
          }
        }
        if step.delayAfter > 0 {
          try? await Task.sleep(
            for: .seconds(step.delayAfter)
          )
        }
      }
      return .succeeded
    case .script(let script):
      guard script.isConfirmed else {
        return .failed(.notConfirmed)
      }
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      guard await scriptExecutionAuthorizer(script) else {
        return .failed(.notConfirmed)
      }
      return await runScript(script)
    }
  }

  public static func shortcut(
    for action: SystemGestureAction
  ) -> KeyboardShortcut? {
    let command = CGEventFlags.maskCommand.rawValue
    let shift = CGEventFlags.maskShift.rawValue
    let control = CGEventFlags.maskControl.rawValue
    let function = CGEventFlags.maskSecondaryFn.rawValue

    switch action {
    case .missionControl:
      return KeyboardShortcut(keyCode: 126, modifiers: control)
    case .showDesktop:
      return KeyboardShortcut(keyCode: 103, modifiers: function)
    case .lockScreen:
      return KeyboardShortcut(
        keyCode: 12,
        modifiers: control | command
      )
    case .volumeUp:
      return KeyboardShortcut(keyCode: 72, modifiers: 0)
    case .volumeDown:
      return KeyboardShortcut(keyCode: 73, modifiers: 0)
    case .mute:
      return KeyboardShortcut(keyCode: 74, modifiers: 0)
    case .brightnessUp:
      return KeyboardShortcut(keyCode: 120, modifiers: function)
    case .brightnessDown:
      return KeyboardShortcut(keyCode: 122, modifiers: function)
    case .appSwitcher:
      return KeyboardShortcut(keyCode: 48, modifiers: command)
    case .spotlight:
      return KeyboardShortcut(keyCode: 49, modifiers: command)
    case .previousSpace:
      return KeyboardShortcut(keyCode: 123, modifiers: control)
    case .nextSpace:
      return KeyboardShortcut(keyCode: 124, modifiers: control)
    case .screenshotFullScreen:
      return KeyboardShortcut(
        keyCode: 20,
        modifiers: shift | command
      )
    case .screenshotSelection:
      return KeyboardShortcut(
        keyCode: 21,
        modifiers: shift | command
      )
    case .screenshotToolbar:
      return KeyboardShortcut(
        keyCode: 23,
        modifiers: shift | command
      )
    case .emojiPicker:
      return KeyboardShortcut(
        keyCode: 49,
        modifiers: control | command
      )
    case .forceQuit:
      return KeyboardShortcut(
        keyCode: 53,
        modifiers: CGEventFlags.maskAlternate.rawValue | command
      )
    case .sleep, .launchpad, .playPause, .previousTrack, .nextTrack:
      return nil
    }
  }

  public static func mediaKeyType(
    for action: SystemGestureAction
  ) -> Int32? {
    switch action {
    case .playPause:
      return 16
    case .nextTrack:
      return 17
    case .previousTrack:
      return 18
    default:
      return nil
    }
  }

  private func launchApplication(
    bundleIdentifier: String
  ) async -> ActionExecutionResult {
    guard
      let applicationURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleIdentifier
      )
    else {
      return .failed(.targetNotFound)
    }

    return await withCheckedContinuation { continuation in
      NSWorkspace.shared.openApplication(
        at: applicationURL,
        configuration: NSWorkspace.OpenConfiguration()
      ) { application, _ in
        continuation.resume(
          returning:
            application == nil
            ? .failed(.launchFailed)
            : .succeeded
        )
      }
    }
  }

  private func executeSystemAction(
    _ action: SystemGestureAction
  ) async -> ActionExecutionResult {
    if let shortcut = Self.shortcut(for: action) {
      return shortcutExecutor.execute(shortcut)
        ? .succeeded
        : .failed(.launchFailed)
    }
    if let keyType = Self.mediaKeyType(for: action) {
      return await MainActor.run {
        SystemMediaKeyExecutor.execute(keyType)
      }
        ? .succeeded
        : .failed(.launchFailed)
    }
    switch action {
    case .launchpad:
      return await runProcess(
        executableURL: URL(fileURLWithPath: "/usr/bin/open"),
        arguments: ["-b", "com.apple.launchpad.launcher"]
      )
    case .sleep:
      return await runProcess(
        executableURL: URL(fileURLWithPath: "/usr/bin/pmset"),
        arguments: ["sleepnow"]
      )
    default:
      return .failed(.invalidAction)
    }
  }

  private func runProcess(
    executableURL: URL,
    arguments: [String]
  ) async -> ActionExecutionResult {
    await withCheckedContinuation { continuation in
      do {
        try Process.run(
          executableURL,
          arguments: arguments
        ) { process in
          continuation.resume(
            returning:
              process.terminationStatus == 0
              ? .succeeded
              : .failed(
                .processFailed(
                  exitCode: process.terminationStatus
                )
              )
          )
        }
      } catch {
        continuation.resume(returning: .failed(.launchFailed))
      }
    }
  }

  private func runScript(
    _ script: AutomationScript
  ) async -> ActionExecutionResult {
    let executableURL: URL
    let arguments: [String]
    switch script.kind {
    case .appleScript:
      executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      arguments = ["-e", script.source]
    case .shell:
      executableURL = URL(fileURLWithPath: "/bin/zsh")
      arguments = ["-c", script.source]
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    let outputPipe = Pipe()
    let outputState = ScriptOutputState(limit: 64 * 1_024)
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty, outputState.record(data.count) {
        process.terminate()
      }
    }

    do {
      try process.run()
    } catch {
      outputPipe.fileHandleForReading.readabilityHandler = nil
      return .failed(.launchFailed)
    }

    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(script.timeout)
    while process.isRunning, clock.now < deadline,
      !outputState.didExceedLimit
    {
      try? await Task.sleep(for: .milliseconds(25))
    }

    let timedOut = process.isRunning && clock.now >= deadline
    if process.isRunning {
      process.terminate()
      for _ in 0..<20 where process.isRunning {
        try? await Task.sleep(for: .milliseconds(10))
      }
    }
    outputPipe.fileHandleForReading.readabilityHandler = nil

    if outputState.didExceedLimit {
      return .failed(.outputLimitExceeded)
    }
    if timedOut {
      return .failed(.timedOut)
    }
    return process.terminationStatus == 0
      ? .succeeded
      : .failed(
        .processFailed(exitCode: process.terminationStatus)
      )
  }
}

public enum WindowLayoutCalculator {
  public static func targetFrame(
    for action: WindowGestureAction,
    currentFrame: CGRect,
    visibleFrame: CGRect
  ) -> CGRect {
    let halfWidth = visibleFrame.width / 2
    let halfHeight = visibleFrame.height / 2

    switch action {
    case .leftHalf:
      return CGRect(
        x: visibleFrame.minX,
        y: visibleFrame.minY,
        width: halfWidth,
        height: visibleFrame.height
      )
    case .rightHalf:
      return CGRect(
        x: visibleFrame.midX,
        y: visibleFrame.minY,
        width: halfWidth,
        height: visibleFrame.height
      )
    case .topHalf:
      return CGRect(
        x: visibleFrame.minX,
        y: visibleFrame.minY,
        width: visibleFrame.width,
        height: halfHeight
      )
    case .bottomHalf:
      return CGRect(
        x: visibleFrame.minX,
        y: visibleFrame.midY,
        width: visibleFrame.width,
        height: halfHeight
      )
    case .topLeftQuarter:
      return CGRect(
        x: visibleFrame.minX,
        y: visibleFrame.minY,
        width: halfWidth,
        height: halfHeight
      )
    case .topRightQuarter:
      return CGRect(
        x: visibleFrame.midX,
        y: visibleFrame.minY,
        width: halfWidth,
        height: halfHeight
      )
    case .bottomLeftQuarter:
      return CGRect(
        x: visibleFrame.minX,
        y: visibleFrame.midY,
        width: halfWidth,
        height: halfHeight
      )
    case .bottomRightQuarter:
      return CGRect(
        x: visibleFrame.midX,
        y: visibleFrame.midY,
        width: halfWidth,
        height: halfHeight
      )
    case .leftThird:
      return CGRect(
        x: visibleFrame.minX,
        y: visibleFrame.minY,
        width: visibleFrame.width / 3,
        height: visibleFrame.height
      )
    case .centerThird:
      return CGRect(
        x: visibleFrame.minX + visibleFrame.width / 3,
        y: visibleFrame.minY,
        width: visibleFrame.width / 3,
        height: visibleFrame.height
      )
    case .rightThird:
      return CGRect(
        x: visibleFrame.minX + visibleFrame.width * 2 / 3,
        y: visibleFrame.minY,
        width: visibleFrame.width / 3,
        height: visibleFrame.height
      )
    case .leftTwoThirds:
      return CGRect(
        x: visibleFrame.minX,
        y: visibleFrame.minY,
        width: visibleFrame.width * 2 / 3,
        height: visibleFrame.height
      )
    case .rightTwoThirds:
      return CGRect(
        x: visibleFrame.minX + visibleFrame.width / 3,
        y: visibleFrame.minY,
        width: visibleFrame.width * 2 / 3,
        height: visibleFrame.height
      )
    case .center:
      let width = min(currentFrame.width, visibleFrame.width)
      let height = min(currentFrame.height, visibleFrame.height)
      return CGRect(
        x: visibleFrame.midX - width / 2,
        y: visibleFrame.midY - height / 2,
        width: width,
        height: height
      )
    case .maximize:
      return visibleFrame
    case .maximizeHeight:
      return CGRect(
        x: max(
          visibleFrame.minX,
          min(currentFrame.minX, visibleFrame.maxX - currentFrame.width)
        ),
        y: visibleFrame.minY,
        width: min(currentFrame.width, visibleFrame.width),
        height: visibleFrame.height
      )
    case .maximizeWidth:
      return CGRect(
        x: visibleFrame.minX,
        y: max(
          visibleFrame.minY,
          min(currentFrame.minY, visibleFrame.maxY - currentFrame.height)
        ),
        width: visibleFrame.width,
        height: min(currentFrame.height, visibleFrame.height)
      )
    case .close, .minimize, .toggleFullScreen, .previousDisplay,
      .nextDisplay, .restorePreviousFrame:
      return currentFrame
    }
  }

  public static func targetFrame(
    for frame: NormalizedWindowFrame,
    visibleFrame: CGRect
  ) -> CGRect {
    guard frame.isValid else { return visibleFrame }
    return CGRect(
      x: visibleFrame.minX + visibleFrame.width * frame.x,
      y: visibleFrame.minY + visibleFrame.height * frame.y,
      width: visibleFrame.width * frame.width,
      height: visibleFrame.height * frame.height
    )
  }

  public static func targetFrameOnAdjacentDisplay(
    currentFrame: CGRect,
    currentVisibleFrame: CGRect,
    targetVisibleFrame: CGRect
  ) -> CGRect {
    let widthRatio =
      currentVisibleFrame.width > 0
      ? currentFrame.width / currentVisibleFrame.width
      : 1
    let heightRatio =
      currentVisibleFrame.height > 0
      ? currentFrame.height / currentVisibleFrame.height
      : 1
    let xRatio =
      currentVisibleFrame.width > currentFrame.width
      ? (currentFrame.minX - currentVisibleFrame.minX)
        / (currentVisibleFrame.width - currentFrame.width)
      : 0
    let yRatio =
      currentVisibleFrame.height > currentFrame.height
      ? (currentFrame.minY - currentVisibleFrame.minY)
        / (currentVisibleFrame.height - currentFrame.height)
      : 0
    let width = min(
      targetVisibleFrame.width,
      targetVisibleFrame.width * widthRatio
    )
    let height = min(
      targetVisibleFrame.height,
      targetVisibleFrame.height * heightRatio
    )
    return CGRect(
      x: targetVisibleFrame.minX
        + max(0, min(1, xRatio)) * (targetVisibleFrame.width - width),
      y: targetVisibleFrame.minY
        + max(0, min(1, yRatio)) * (targetVisibleFrame.height - height),
      width: width,
      height: height
    )
  }
}

@MainActor
private enum WindowGestureActionExecutor {
  private struct WindowKey: Hashable {
    let processIdentifier: pid_t
    let elementHash: CFHashCode
  }

  private struct Context {
    let window: AXUIElement
    let key: WindowKey
    let currentFrame: CGRect
    let visibleFrames: [CGRect]
    let currentDisplayIndex: Int
  }

  private static var previousFrames: [WindowKey: CGRect] = [:]

  static func execute(
    _ action: WindowGestureAction
  ) -> ActionExecutionResult {
    guard let context = context() else {
      return .failed(.targetNotFound)
    }

    switch action {
    case .close:
      return performClose(on: context.window)
    case .minimize:
      return setBooleanAttribute(
        kAXMinimizedAttribute,
        value: true,
        on: context.window
      )
    case .toggleFullScreen:
      return toggleBooleanAttribute(
        "AXFullScreen",
        on: context.window
      )
    case .previousDisplay, .nextDisplay:
      guard context.visibleFrames.count > 1 else {
        return .failed(.targetNotFound)
      }
      let offset = action == .nextDisplay ? 1 : -1
      let targetIndex =
        (context.currentDisplayIndex + offset
          + context.visibleFrames.count) % context.visibleFrames.count
      let targetFrame =
        WindowLayoutCalculator.targetFrameOnAdjacentDisplay(
          currentFrame: context.currentFrame,
          currentVisibleFrame:
            context.visibleFrames[context.currentDisplayIndex],
          targetVisibleFrame: context.visibleFrames[targetIndex]
        )
      return setFrame(
        targetFrame,
        on: context,
        rememberCurrentFrame: true
      )
    case .restorePreviousFrame:
      guard let previousFrame = previousFrames[context.key] else {
        return .failed(.targetNotFound)
      }
      let result = setFrame(
        previousFrame,
        on: context,
        rememberCurrentFrame: false
      )
      if result == .succeeded {
        previousFrames[context.key] = context.currentFrame
      }
      return result
    default:
      let visibleFrame =
        context.visibleFrames[context.currentDisplayIndex]
      let targetFrame = WindowLayoutCalculator.targetFrame(
        for: action,
        currentFrame: context.currentFrame,
        visibleFrame: visibleFrame
      )
      return setFrame(
        targetFrame,
        on: context,
        rememberCurrentFrame: true
      )
    }
  }

  static func execute(
    _ frame: NormalizedWindowFrame
  ) -> ActionExecutionResult {
    guard frame.isValid else {
      return .failed(.invalidAction)
    }
    guard let context = context() else {
      return .failed(.targetNotFound)
    }
    let targetFrame = WindowLayoutCalculator.targetFrame(
      for: frame,
      visibleFrame:
        context.visibleFrames[context.currentDisplayIndex]
    )
    return setFrame(
      targetFrame,
      on: context,
      rememberCurrentFrame: true
    )
  }

  private static func context() -> Context? {
    guard
      let application = NSWorkspace.shared.frontmostApplication,
      application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else {
      return nil
    }

    let applicationElement = AXUIElementCreateApplication(
      application.processIdentifier
    )
    var focusedWindowValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        applicationElement,
        kAXFocusedWindowAttribute as CFString,
        &focusedWindowValue
      ) == .success,
      let focusedWindowValue,
      CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
    else {
      return nil
    }
    let window = focusedWindowValue as! AXUIElement
    guard
      let currentPosition = pointAttribute(
        kAXPositionAttribute,
        from: window
      ),
      let currentSize = sizeAttribute(
        kAXSizeAttribute,
        from: window
      )
    else {
      return nil
    }

    let currentFrame = CGRect(
      origin: currentPosition,
      size: currentSize
    )
    let visibleFrames = visibleFrames()
    guard !visibleFrames.isEmpty else { return nil }
    let currentDisplayIndex =
      visibleFrames.indices.max {
        intersectionArea(visibleFrames[$0], currentFrame)
          < intersectionArea(visibleFrames[$1], currentFrame)
      } ?? 0
    return Context(
      window: window,
      key: WindowKey(
        processIdentifier: application.processIdentifier,
        elementHash: CFHash(window)
      ),
      currentFrame: currentFrame,
      visibleFrames: visibleFrames,
      currentDisplayIndex: currentDisplayIndex
    )
  }

  private static func setFrame(
    _ frame: CGRect,
    on context: Context,
    rememberCurrentFrame: Bool
  ) -> ActionExecutionResult {
    let targetFrame = frame.integral
    var targetPosition = targetFrame.origin
    var targetSize = targetFrame.size
    guard
      let positionValue = AXValueCreate(
        .cgPoint,
        &targetPosition
      ),
      let sizeValue = AXValueCreate(.cgSize, &targetSize)
    else {
      return .failed(.launchFailed)
    }
    let sizeResult = AXUIElementSetAttributeValue(
      context.window,
      kAXSizeAttribute as CFString,
      sizeValue
    )
    let positionResult = AXUIElementSetAttributeValue(
      context.window,
      kAXPositionAttribute as CFString,
      positionValue
    )
    guard sizeResult == .success, positionResult == .success else {
      return .failed(.launchFailed)
    }
    if rememberCurrentFrame {
      previousFrames[context.key] = context.currentFrame
      if previousFrames.count > 100,
        let firstKey = previousFrames.keys.first
      {
        previousFrames.removeValue(forKey: firstKey)
      }
    }
    return .succeeded
  }

  private static func performClose(
    on window: AXUIElement
  ) -> ActionExecutionResult {
    var closeButtonValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        window,
        kAXCloseButtonAttribute as CFString,
        &closeButtonValue
      ) == .success,
      let closeButtonValue,
      CFGetTypeID(closeButtonValue) == AXUIElementGetTypeID()
    else {
      return .failed(.targetNotFound)
    }
    return AXUIElementPerformAction(
      closeButtonValue as! AXUIElement,
      kAXPressAction as CFString
    ) == .success
      ? .succeeded
      : .failed(.launchFailed)
  }

  private static func setBooleanAttribute(
    _ attribute: String,
    value: Bool,
    on window: AXUIElement
  ) -> ActionExecutionResult {
    AXUIElementSetAttributeValue(
      window,
      attribute as CFString,
      value ? kCFBooleanTrue : kCFBooleanFalse
    ) == .success
      ? .succeeded
      : .failed(.launchFailed)
  }

  private static func toggleBooleanAttribute(
    _ attribute: String,
    on window: AXUIElement
  ) -> ActionExecutionResult {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        window,
        attribute as CFString,
        &value
      ) == .success,
      let value,
      CFGetTypeID(value) == CFBooleanGetTypeID()
    else {
      return .failed(.targetNotFound)
    }
    return setBooleanAttribute(
      attribute,
      value: !CFBooleanGetValue((value as! CFBoolean)),
      on: window
    )
  }

  private static func pointAttribute(
    _ attribute: String,
    from element: AXUIElement
  ) -> CGPoint? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
      ) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }
    var point = CGPoint.zero
    guard
      AXValueGetValue(value as! AXValue, .cgPoint, &point)
    else {
      return nil
    }
    return point
  }

  private static func sizeAttribute(
    _ attribute: String,
    from element: AXUIElement
  ) -> CGSize? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
      ) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }
    var size = CGSize.zero
    guard
      AXValueGetValue(value as! AXValue, .cgSize, &size)
    else {
      return nil
    }
    return size
  }

  private static func visibleFrames() -> [CGRect] {
    let screens = NSScreen.screens
    guard !screens.isEmpty else { return [] }
    let primaryTop =
      screens.first(where: {
        guard
          let number = $0.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
          ] as? NSNumber
        else {
          return false
        }
        return CGDirectDisplayID(number.uint32Value)
          == CGMainDisplayID()
      })?.frame.maxY
      ?? screens[0].frame.maxY
    return screens.map {
      CGRect(
        x: $0.visibleFrame.minX,
        y: primaryTop - $0.visibleFrame.maxY,
        width: $0.visibleFrame.width,
        height: $0.visibleFrame.height
      )
    }.sorted {
      if $0.minX == $1.minX {
        return $0.minY < $1.minY
      }
      return $0.minX < $1.minX
    }
  }

  private static func intersectionArea(
    _ left: CGRect,
    _ right: CGRect
  ) -> CGFloat {
    let intersection = left.intersection(right)
    guard !intersection.isNull else { return 0 }
    return intersection.width * intersection.height
  }
}

@MainActor
private enum SyntheticTextInputExecutor {
  static func execute(_ text: String) -> Bool {
    let utf16 = Array(text.utf16)
    guard !utf16.isEmpty,
      let source = CGEventSource(stateID: .hidSystemState),
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0,
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0,
        keyDown: false
      )
    else {
      return false
    }
    utf16.withUnsafeBufferPointer { buffer in
      guard let address = buffer.baseAddress else { return }
      keyDown.keyboardSetUnicodeString(
        stringLength: buffer.count,
        unicodeString: address
      )
      keyUp.keyboardSetUnicodeString(
        stringLength: buffer.count,
        unicodeString: address
      )
    }
    for event in [keyDown, keyUp] {
      event.setIntegerValueField(
        .eventSourceUserData,
        value: EventSourceMarker.syntheticEventUserData
      )
      event.post(tap: .cgSessionEventTap)
    }
    return true
  }
}

@MainActor
private enum SystemMediaKeyExecutor {
  static func execute(_ keyType: Int32) -> Bool {
    for isKeyDown in [true, false] {
      let keyState = isKeyDown ? 0xA : 0xB
      guard
        let event = NSEvent.otherEvent(
          with: .systemDefined,
          location: .zero,
          modifierFlags: [],
          timestamp: 0,
          windowNumber: 0,
          context: nil,
          subtype: 8,
          data1: Int((keyType << 16) | (Int32(keyState) << 8)),
          data2: -1
        )?.cgEvent
      else {
        return false
      }
      event.setIntegerValueField(
        .eventSourceUserData,
        value: EventSourceMarker.syntheticEventUserData
      )
      event.post(tap: .cgSessionEventTap)
    }
    return true
  }
}

@MainActor
private enum ApplicationMenuActionExecutor {
  static func execute(
    _ action: ApplicationMenuAction
  ) -> ActionExecutionResult {
    guard
      let application = NSWorkspace.shared.frontmostApplication,
      application.processIdentifier
        != ProcessInfo.processInfo.processIdentifier
    else {
      return .failed(.targetNotFound)
    }
    let applicationElement = AXUIElementCreateApplication(
      application.processIdentifier
    )
    var menuBarValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        applicationElement,
        kAXMenuBarAttribute as CFString,
        &menuBarValue
      ) == .success,
      let menuBarValue,
      CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
    else {
      return .failed(.targetNotFound)
    }

    var current = menuBarValue as! AXUIElement
    for (index, title) in action.normalizedPath.enumerated() {
      guard
        let item = firstDescendant(
          titled: title,
          in: current,
          maximumDepth: 4
        )
      else {
        return .failed(.targetNotFound)
      }
      if index == action.normalizedPath.count - 1 {
        return AXUIElementPerformAction(
          item,
          kAXPressAction as CFString
        ) == .success
          ? .succeeded
          : .failed(.launchFailed)
      }
      current = item
    }
    return .failed(.targetNotFound)
  }

  private static func firstDescendant(
    titled title: String,
    in element: AXUIElement,
    maximumDepth: Int
  ) -> AXUIElement? {
    guard maximumDepth >= 0 else { return nil }
    for child in children(of: element) {
      if elementTitle(of: child) == title {
        return child
      }
      if let match = firstDescendant(
        titled: title,
        in: child,
        maximumDepth: maximumDepth - 1
      ) {
        return match
      }
    }
    return nil
  }

  private static func children(
    of element: AXUIElement
  ) -> [AXUIElement] {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXChildrenAttribute as CFString,
        &value
      ) == .success,
      let children = value as? [AXUIElement]
    else {
      return []
    }
    return children
  }

  private static func elementTitle(
    of element: AXUIElement
  ) -> String? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXTitleAttribute as CFString,
        &value
      ) == .success
    else {
      return nil
    }
    return value as? String
  }
}

private final class ScriptOutputState: @unchecked Sendable {
  private let lock = NSLock()
  private let limit: Int
  private var count = 0

  init(limit: Int) {
    self.limit = limit
  }

  var didExceedLimit: Bool {
    lock.lock()
    defer { lock.unlock() }
    return count > limit
  }

  func record(_ byteCount: Int) -> Bool {
    lock.lock()
    count += byteCount
    let exceeded = count > limit
    lock.unlock()
    return exceeded
  }
}

public actor ActionDispatcher {
  public typealias ResultHandler =
    @Sendable (ActionRequest, ActionExecutionResult) -> Void

  private struct PendingAction: Sendable {
    let request: ActionRequest
    let continuation: CheckedContinuation<Void, Never>
  }

  private let executor: any ActionExecuting
  private let resultHandler: ResultHandler?
  private var pendingActions: [PendingAction] = []
  private var isDraining = false

  public init(
    executor: any ActionExecuting = SystemGestureActionExecutor(),
    resultHandler: ResultHandler? = nil
  ) {
    self.executor = executor
    self.resultHandler = resultHandler
  }

  public func submit(_ request: ActionRequest) async {
    await withCheckedContinuation { continuation in
      pendingActions.append(
        PendingAction(
          request: request,
          continuation: continuation
        )
      )
      guard !isDraining else { return }
      isDraining = true
      Task {
        await drain()
      }
    }
  }

  private func drain() async {
    while !pendingActions.isEmpty {
      let pending = pendingActions.removeFirst()
      let result = await executor.execute(pending.request)
      resultHandler?(pending.request, result)
      pending.continuation.resume()
    }
    isDraining = false
  }
}
