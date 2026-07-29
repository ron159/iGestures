import XCTest

@testable import iGestures

@MainActor
final class PermissionCoordinatorTests: XCTestCase {
  func testInitialMissingPermissionNeedsUserAction() {
    let provider = PermissionProviderStub(
      diagnostics: deniedDiagnostics
    )
    let coordinator = PermissionCoordinator(provider: provider)

    XCTAssertEqual(coordinator.refresh(), .needsUserAction)
    XCTAssertEqual(provider.promptValues, [false])
  }

  func testPermissionPromptIsOnlyExplicitlyRequested() {
    let provider = PermissionProviderStub(
      diagnostics: deniedDiagnostics
    )
    let coordinator = PermissionCoordinator(provider: provider)

    XCTAssertEqual(coordinator.requestAccess(), .checking)
    XCTAssertEqual(provider.promptValues, [true])
    XCTAssertEqual(provider.listenRequestCount, 1)
    XCTAssertEqual(provider.postRequestCount, 1)
    XCTAssertEqual(coordinator.refresh(), .denied)
    XCTAssertEqual(provider.promptValues, [true, false])
  }

  func testEachEventPermissionCanBeRequestedDirectly() {
    let provider = PermissionProviderStub(
      diagnostics: deniedDiagnostics
    )
    let coordinator = PermissionCoordinator(provider: provider)

    XCTAssertEqual(
      coordinator.requestListenEventAccess(),
      .checking
    )
    XCTAssertEqual(provider.listenRequestCount, 1)
    XCTAssertEqual(provider.postRequestCount, 0)

    XCTAssertEqual(
      coordinator.requestPostEventAccess(),
      .checking
    )
    XCTAssertEqual(provider.listenRequestCount, 1)
    XCTAssertEqual(provider.postRequestCount, 1)
  }

  func testTrustedPermissionWaitsForEventTapCreation() {
    let provider = PermissionProviderStub(
      diagnostics: grantedDiagnostics
    )
    let coordinator = PermissionCoordinator(provider: provider)

    XCTAssertEqual(coordinator.refresh(), .checking)
    XCTAssertEqual(
      coordinator.recordEventTapCreation(succeeded: true),
      .granted
    )
  }

  func testEventTapFailureIsReportedSeparately() {
    let provider = PermissionProviderStub(
      diagnostics: grantedDiagnostics
    )
    let coordinator = PermissionCoordinator(provider: provider)

    _ = coordinator.refresh()
    XCTAssertEqual(
      coordinator.recordEventTapCreation(succeeded: false),
      .tapCreationFailed
    )
  }

  private var deniedDiagnostics: PermissionDiagnostics {
    PermissionDiagnostics(
      accessibilityTrusted: false,
      listenEventAccess: false,
      postEventAccess: false
    )
  }

  private var grantedDiagnostics: PermissionDiagnostics {
    PermissionDiagnostics(
      accessibilityTrusted: true,
      listenEventAccess: true,
      postEventAccess: true
    )
  }
}

@MainActor
private final class PermissionProviderStub: PermissionProviding {
  let value: PermissionDiagnostics
  private(set) var promptValues: [Bool] = []
  private(set) var listenRequestCount = 0
  private(set) var postRequestCount = 0

  init(diagnostics: PermissionDiagnostics) {
    value = diagnostics
  }

  func diagnostics(
    promptForAccessibility: Bool
  ) -> PermissionDiagnostics {
    promptValues.append(promptForAccessibility)
    return value
  }

  func requestListenEventAccess() -> Bool {
    listenRequestCount += 1
    return value.listenEventAccess
  }

  func requestPostEventAccess() -> Bool {
    postRequestCount += 1
    return value.postEventAccess
  }
}
