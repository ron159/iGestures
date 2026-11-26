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

  func testEnableRegistersWhenSystemCannotFindLoginItem() throws {
    let provider = LoginItemProviderStub(state: .notFound)
    let controller = LoginItemController(provider: provider)

    XCTAssertEqual(try controller.setEnabled(true), .enabled)
    XCTAssertEqual(provider.registerCount, 1)
  }

  func testEnableFromNotFoundRefreshesToRequiresApproval() throws {
    let provider = LoginItemProviderStub(
      state: .notFound,
      registeredState: .requiresApproval
    )
    let controller = LoginItemController(provider: provider)

    XCTAssertEqual(try controller.setEnabled(true), .requiresApproval)
    XCTAssertEqual(provider.registerCount, 1)
  }

  func testFailedRegistrationCanBeRetriedFromNotFound() throws {
    let provider = LoginItemProviderStub(state: .notFound)
    provider.registrationError = CocoaError(.fileNoSuchFile)
    let controller = LoginItemController(provider: provider)

    XCTAssertThrowsError(try controller.setEnabled(true))
    XCTAssertEqual(controller.refresh(), .notFound)

    provider.registrationError = nil
    XCTAssertEqual(try controller.setEnabled(true), .enabled)
    XCTAssertEqual(provider.registerCount, 2)
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
  var registrationError: CocoaError?
  private let registeredState: LoginItemState

  init(state: LoginItemState, registeredState: LoginItemState = .enabled) {
    self.state = state
    self.registeredState = registeredState
  }

  func register() throws {
    registerCount += 1
    if let registrationError {
      throw registrationError
    }
    state = registeredState
  }

  func unregister() {
    unregisterCount += 1
    state = .notRegistered
  }

  func openSystemSettings() {
    openSettingsCount += 1
  }
}
