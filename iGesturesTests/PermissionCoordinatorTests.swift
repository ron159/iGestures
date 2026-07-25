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
    XCTAssertEqual(coordinator.refresh(), .denied)
    XCTAssertEqual(provider.promptValues, [true, false])
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

  init(diagnostics: PermissionDiagnostics) {
    value = diagnostics
  }

  func diagnostics(
    promptForAccessibility: Bool
  ) -> PermissionDiagnostics {
    promptValues.append(promptForAccessibility)
    return value
  }
}
