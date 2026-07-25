import ServiceManagement

public enum LoginItemState: Equatable, Sendable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
}

@MainActor
public protocol LoginItemProviding {
  var state: LoginItemState { get }
  func register() throws
  func unregister() throws
  func openSystemSettings()
}

@MainActor
public struct SystemLoginItemProvider: LoginItemProviding {
  public init() {}

  public var state: LoginItemState {
    switch SMAppService.mainApp.status {
    case .notRegistered:
      .notRegistered
    case .enabled:
      .enabled
    case .requiresApproval:
      .requiresApproval
    case .notFound:
      .notFound
    @unknown default:
      .notFound
    }
  }

  public func register() throws {
    try SMAppService.mainApp.register()
  }

  public func unregister() throws {
    try SMAppService.mainApp.unregister()
  }

  public func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

@MainActor
public final class LoginItemController {
  public private(set) var state: LoginItemState

  private let provider: any LoginItemProviding

  public init(provider: (any LoginItemProviding)? = nil) {
    let provider = provider ?? SystemLoginItemProvider()
    self.provider = provider
    self.state = provider.state
  }

  @discardableResult
  public func refresh() -> LoginItemState {
    state = provider.state
    return state
  }

  @discardableResult
  public func setEnabled(_ isEnabled: Bool) throws -> LoginItemState {
    if isEnabled {
      if provider.state == .notRegistered {
        try provider.register()
      }
    } else if provider.state != .notRegistered {
      try provider.unregister()
    }
    return refresh()
  }

  public func openSystemSettings() {
    provider.openSystemSettings()
  }
}
