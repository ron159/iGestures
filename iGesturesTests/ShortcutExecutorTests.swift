import XCTest

@testable import iGestures

final class ShortcutExecutorTests: XCTestCase {
  func testEventSequenceContainsMarkedKeyDownAndKeyUp() {
    let shortcut = KeyboardShortcut(
      keyCode: 12,
      modifiers: 0x18_0000
    )

    let events = SystemShortcutExecutor.eventSequence(for: shortcut)

    XCTAssertEqual(
      events,
      [
        KeyboardEventDescriptor(
          keyCode: 12,
          modifiers: 0x18_0000,
          isKeyDown: true,
          sourceUserData: EventSourceMarker.syntheticEventUserData
        ),
        KeyboardEventDescriptor(
          keyCode: 12,
          modifiers: 0x18_0000,
          isKeyDown: false,
          sourceUserData: EventSourceMarker.syntheticEventUserData
        ),
      ]
    )
  }

  func testInvalidShortcutProducesNoEvents() {
    XCTAssertTrue(
      SystemShortcutExecutor.eventSequence(
        for: KeyboardShortcut(keyCode: .max, modifiers: 0)
      ).isEmpty
    )
  }

  func testEverySystemActionHasAnExecutionRoute() {
    for action in SystemGestureAction.allCases {
      if action == .sleep {
        XCTAssertNil(SystemGestureActionExecutor.shortcut(for: action))
      } else {
        XCTAssertNotNil(SystemGestureActionExecutor.shortcut(for: action))
      }
    }
  }

  func testActionDispatcherReturnsExecutorResult() async {
    let request = ActionRequest(
      mappingID: UUID(),
      mappingName: "Test",
      action: .openURL("https://example.com")
    )
    let expectation = expectation(description: "result")
    let dispatcher = ActionDispatcher(
      executor: StubActionExecutor(result: .failed(.launchFailed))
    ) { returnedRequest, result in
      XCTAssertEqual(returnedRequest, request)
      XCTAssertEqual(result, .failed(.launchFailed))
      expectation.fulfill()
    }

    await dispatcher.submit(request)
    await fulfillment(of: [expectation], timeout: 1)
  }

  func testActionDispatcherLimitsConcurrentExecutionToOne() async {
    let executor = ConcurrencyProbeExecutor()
    let dispatcher = ActionDispatcher(executor: executor)
    let requests = (0..<4).map {
      ActionRequest(
        mappingID: UUID(),
        mappingName: "Request \($0)",
        action: .openURL("https://example.com/\($0)")
      )
    }

    await withTaskGroup(of: Void.self) { group in
      for request in requests {
        group.addTask {
          await dispatcher.submit(request)
        }
      }
      await group.waitForAll()
    }

    let maximumConcurrentExecutions =
      await executor.maximumConcurrentExecutions
    XCTAssertEqual(maximumConcurrentExecutions, 1)
  }

  func testSequenceRunsInOrderAndContinuesAfterFailure() async {
    let shortcutExecutor = RecordingShortcutExecutor(
      outcomes: [1: false, 2: true]
    )
    let executor = SystemGestureActionExecutor(
      shortcutExecutor: shortcutExecutor
    )
    let request = ActionRequest(
      mappingID: UUID(),
      mappingName: "Sequence",
      action: .sequence(
        GestureActionSequence(
          steps: [
            GestureActionStep(
              action: .keyboardShortcut(
                KeyboardShortcut(keyCode: 1, modifiers: 0)
              )
            ),
            GestureActionStep(
              action: .keyboardShortcut(
                KeyboardShortcut(keyCode: 2, modifiers: 0)
              )
            ),
          ],
          failurePolicy: .continue
        )
      )
    )

    let result = await executor.execute(request)

    XCTAssertEqual(result, .succeeded)
    XCTAssertEqual(shortcutExecutor.executedKeyCodes, [1, 2])
  }

  func testSequenceRunsFallbackAndStopsRemainingSteps() async {
    let shortcutExecutor = RecordingShortcutExecutor(
      outcomes: [1: false, 2: true, 3: true]
    )
    let executor = SystemGestureActionExecutor(
      shortcutExecutor: shortcutExecutor
    )
    let request = ActionRequest(
      mappingID: UUID(),
      mappingName: "Fallback",
      action: .sequence(
        GestureActionSequence(
          steps: [
            GestureActionStep(
              action: .keyboardShortcut(
                KeyboardShortcut(keyCode: 1, modifiers: 0)
              )
            ),
            GestureActionStep(
              action: .keyboardShortcut(
                KeyboardShortcut(keyCode: 2, modifiers: 0)
              )
            ),
          ],
          failurePolicy: .fallback(
            .keyboardShortcut(
              KeyboardShortcut(keyCode: 3, modifiers: 0)
            )
          )
        )
      )
    )

    let result = await executor.execute(request)

    XCTAssertEqual(result, .succeeded)
    XCTAssertEqual(shortcutExecutor.executedKeyCodes, [1, 3])
  }

  func testConfirmedScriptIsTerminatedAtTimeout() async {
    let executor = SystemGestureActionExecutor()
    let request = ActionRequest(
      mappingID: UUID(),
      mappingName: "Timed Script",
      action: .script(
        AutomationScript(
          kind: .shell,
          source: "sleep 5",
          timeout: 1,
          isConfirmed: true
        )
      )
    )

    let result = await executor.execute(request)

    XCTAssertEqual(result, .failed(.timedOut))
  }
}

private struct StubActionExecutor: ActionExecuting {
  let result: ActionExecutionResult

  func execute(
    _ request: ActionRequest
  ) async -> ActionExecutionResult {
    result
  }
}

private actor ConcurrencyProbeExecutor: ActionExecuting {
  private var activeExecutions = 0
  private(set) var maximumConcurrentExecutions = 0

  func execute(
    _ request: ActionRequest
  ) async -> ActionExecutionResult {
    activeExecutions += 1
    maximumConcurrentExecutions = max(
      maximumConcurrentExecutions,
      activeExecutions
    )
    try? await Task.sleep(for: .milliseconds(20))
    activeExecutions -= 1
    return .succeeded
  }
}

private final class RecordingShortcutExecutor:
  ShortcutExecuting,
  @unchecked Sendable
{
  private let lock = NSLock()
  private let outcomes: [UInt16: Bool]
  private var keyCodes: [UInt16] = []

  init(outcomes: [UInt16: Bool]) {
    self.outcomes = outcomes
  }

  var executedKeyCodes: [UInt16] {
    lock.lock()
    defer { lock.unlock() }
    return keyCodes
  }

  func execute(_ shortcut: KeyboardShortcut) -> Bool {
    lock.lock()
    keyCodes.append(shortcut.keyCode)
    let result = outcomes[shortcut.keyCode] ?? true
    lock.unlock()
    return result
  }
}
