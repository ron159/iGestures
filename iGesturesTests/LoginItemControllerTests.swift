import XCTest

@testable import iGestures

@MainActor
final class LoginItemControllerTests: XCTestCase {
  func testEnableRegistersAndRefreshesState() throws {
    let provider = LoginItemProviderStub(state: .notRegistered)
    let controller = LoginItemController(provider: provider)

    XCTAssertEqual(try controller.setEnabled(true), .enabled)
    XCTAssertEqual(provider.registerCount, 1)
    XCTAssertEqual(provider.unregisterCount, 0)
  }

  func testDisableUnregistersEnabledService() throws {
    let provider = LoginItemProviderStub(state: .enabled)
    let controller = LoginItemController(provider: provider)

    XCTAssertEqual(
      try controller.setEnabled(false),
      .notRegistered
    )
    XCTAssertEqual(provider.unregisterCount, 1)
  }

  func testRequiresApprovalDoesNotRegisterAgain() throws {
    let provider = LoginItemProviderStub(state: .requiresApproval)
    let controller = LoginItemController(provider: provider)

    XCTAssertEqual(
      try controller.setEnabled(true),
      .requiresApproval
    )
    XCTAssertEqual(provider.registerCount, 0)
  }

  func testSystemSettingsRequestIsForwarded() {
    let provider = LoginItemProviderStub(state: .requiresApproval)
    let controller = LoginItemController(provider: provider)

    controller.openSystemSettings()

    XCTAssertEqual(provider.openSettingsCount, 1)
  }
}

@MainActor
private final class LoginItemProviderStub: LoginItemProviding {
  private(set) var state: LoginItemState
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0
  private(set) var openSettingsCount = 0

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

  func openSystemSettings() {
    openSettingsCount += 1
  }
}
