import AppKit
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
    case .launchApplication(let bundleIdentifier):
      guard action.isValid else {
        return .failed(.invalidAction)
      }
      return await launchApplication(
        bundleIdentifier: bundleIdentifier
      )
    case .system(let action):
      return await executeSystemAction(action)
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
    case .sleep:
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
    return await runProcess(
      executableURL: URL(fileURLWithPath: "/usr/bin/pmset"),
      arguments: ["sleepnow"]
    )
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
