import XCTest

@testable import iGestures

final class ShortcutExecutorTests: XCTestCase {
  func testNoActionCompletesWithoutExecutingAnything() async {
    let request = ActionRequest(
      mappingID: UUID(),
      mappingName: "None",
      action: .none
    )

    let result = await SystemGestureActionExecutor().execute(request)

    XCTAssertEqual(result, .succeeded)
  }

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
      let hasShortcut =
        SystemGestureActionExecutor.shortcut(for: action) != nil
      let hasMediaKey =
        SystemGestureActionExecutor.mediaKeyType(for: action) != nil
      let hasProcessRoute = action == .sleep || action == .launchpad
      XCTAssertTrue(
        hasShortcut || hasMediaKey || hasProcessRoute,
        "\(action) has no execution route"
      )
    }
  }

  func testWindowLayoutTargetsVisibleScreenRegions() {
    let visibleFrame = CGRect(x: 100, y: 50, width: 1200, height: 800)
    let currentFrame = CGRect(x: 300, y: 200, width: 600, height: 400)

    XCTAssertEqual(
      WindowLayoutCalculator.targetFrame(
        for: .leftHalf,
        currentFrame: currentFrame,
        visibleFrame: visibleFrame
      ),
      CGRect(x: 100, y: 50, width: 600, height: 800)
    )
    XCTAssertEqual(
      WindowLayoutCalculator.targetFrame(
        for: .bottomRightQuarter,
        currentFrame: currentFrame,
        visibleFrame: visibleFrame
      ),
      CGRect(x: 700, y: 450, width: 600, height: 400)
    )
    XCTAssertEqual(
      WindowLayoutCalculator.targetFrame(
        for: .center,
        currentFrame: currentFrame,
        visibleFrame: visibleFrame
      ),
      CGRect(x: 400, y: 250, width: 600, height: 400)
    )
    XCTAssertEqual(
      WindowLayoutCalculator.targetFrame(
        for: .maximize,
        currentFrame: currentFrame,
        visibleFrame: visibleFrame
      ),
      visibleFrame
    )
    XCTAssertEqual(
      WindowLayoutCalculator.targetFrame(
        for: .topHalf,
        currentFrame: currentFrame,
        visibleFrame: visibleFrame
      ),
      CGRect(x: 100, y: 50, width: 1200, height: 400)
    )
    XCTAssertEqual(
      WindowLayoutCalculator.targetFrame(
        for: .rightThird,
        currentFrame: currentFrame,
        visibleFrame: visibleFrame
      ),
      CGRect(x: 900, y: 50, width: 400, height: 800)
    )
    for action in WindowGestureAction.allCases {
      let frame = WindowLayoutCalculator.targetFrame(
        for: action,
        currentFrame: currentFrame,
        visibleFrame: visibleFrame
      )
      XCTAssertGreaterThan(frame.width, 0)
      XCTAssertGreaterThan(frame.height, 0)
      XCTAssertTrue(visibleFrame.contains(frame))
    }
  }

  func testCustomAndAdjacentDisplayWindowLayouts() {
    let currentVisibleFrame = CGRect(
      x: 0,
      y: 0,
      width: 1000,
      height: 800
    )
    let targetVisibleFrame = CGRect(
      x: 1000,
      y: 0,
      width: 2000,
      height: 1200
    )
    let currentFrame = CGRect(x: 250, y: 200, width: 500, height: 400)

    XCTAssertEqual(
      WindowLayoutCalculator.targetFrame(
        for: NormalizedWindowFrame(
          x: 0.1,
          y: 0.2,
          width: 0.6,
          height: 0.5
        ),
        visibleFrame: currentVisibleFrame
      ),
      CGRect(x: 100, y: 160, width: 600, height: 400)
    )
    XCTAssertEqual(
      WindowLayoutCalculator.targetFrameOnAdjacentDisplay(
        currentFrame: currentFrame,
        currentVisibleFrame: currentVisibleFrame,
        targetVisibleFrame: targetVisibleFrame
      ),
      CGRect(x: 1500, y: 300, width: 1000, height: 600)
    )
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

  @MainActor
  func testConfirmedScriptRequiresFirstExecutionAuthorization() async {
    var authorizationRequests = 0
    let executor = SystemGestureActionExecutor(
      scriptExecutionAuthorizer: { _ in
        authorizationRequests += 1
        return false
      }
    )
    let request = ActionRequest(
      mappingID: UUID(),
      mappingName: "Rejected Script",
      action: .script(
        AutomationScript(
          kind: .shell,
          source: "exit 0",
          isConfirmed: true
        )
      )
    )

    let result = await executor.execute(request)

    XCTAssertEqual(result, .failed(.notConfirmed))
    XCTAssertEqual(authorizationRequests, 1)
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
