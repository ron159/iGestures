@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

public enum PermissionState: Equatable, Sendable {
  case unknown
  case needsUserAction
  case checking
  case granted
  case denied
  case tapCreationFailed
}

public struct PermissionDiagnostics: Equatable, Sendable {
  public let accessibilityTrusted: Bool
  public let listenEventAccess: Bool
  public let postEventAccess: Bool

  public init(
    accessibilityTrusted: Bool,
    listenEventAccess: Bool,
    postEventAccess: Bool
  ) {
    self.accessibilityTrusted = accessibilityTrusted
    self.listenEventAccess = listenEventAccess
    self.postEventAccess = postEventAccess
  }
}

@MainActor
public protocol PermissionProviding {
  func diagnostics(promptForAccessibility: Bool) -> PermissionDiagnostics
  func requestListenEventAccess() -> Bool
  func requestPostEventAccess() -> Bool
}

@MainActor
public struct SystemPermissionProvider: PermissionProviding {
  public init() {}

  public func diagnostics(
    promptForAccessibility: Bool
  ) -> PermissionDiagnostics {
    let accessibilityTrusted: Bool
    if promptForAccessibility {
      let options =
        [
          kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
      accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    } else {
      accessibilityTrusted = AXIsProcessTrusted()
    }

    return PermissionDiagnostics(
      accessibilityTrusted: accessibilityTrusted,
      listenEventAccess: CGPreflightListenEventAccess(),
      postEventAccess: CGPreflightPostEventAccess()
    )
  }

  public func requestListenEventAccess() -> Bool {
    CGRequestListenEventAccess()
  }

  public func requestPostEventAccess() -> Bool {
    CGRequestPostEventAccess()
  }
}

@MainActor
public final class PermissionCoordinator {
  public private(set) var state: PermissionState = .unknown
  public private(set) var diagnostics = PermissionDiagnostics(
    accessibilityTrusted: false,
    listenEventAccess: false,
    postEventAccess: false
  )

  private let provider: any PermissionProviding
  private var hasRequestedAccess = false

  public init(provider: (any PermissionProviding)? = nil) {
    self.provider = provider ?? SystemPermissionProvider()
  }

  @discardableResult
  public func refresh() -> PermissionState {
    diagnostics = provider.diagnostics(promptForAccessibility: false)
    if hasAllRequiredAccess {
      state = .checking
    } else {
      state = hasRequestedAccess ? .denied : .needsUserAction
    }
    return state
  }

  @discardableResult
  public func requestAccess() -> PermissionState {
    hasRequestedAccess = true
    let current = provider.diagnostics(promptForAccessibility: true)
    diagnostics = PermissionDiagnostics(
      accessibilityTrusted: current.accessibilityTrusted,
      listenEventAccess:
        current.listenEventAccess
        || provider.requestListenEventAccess(),
      postEventAccess:
        current.postEventAccess
        || provider.requestPostEventAccess()
    )
    state = .checking
    return state
  }

  @discardableResult
  public func requestAccessibilityAccess() -> PermissionState {
    hasRequestedAccess = true
    diagnostics = provider.diagnostics(promptForAccessibility: true)
    state = .checking
    return state
  }

  @discardableResult
  public func requestListenEventAccess() -> PermissionState {
    hasRequestedAccess = true
    let current = provider.diagnostics(promptForAccessibility: false)
    diagnostics = PermissionDiagnostics(
      accessibilityTrusted: current.accessibilityTrusted,
      listenEventAccess:
        current.listenEventAccess
        || provider.requestListenEventAccess(),
      postEventAccess: current.postEventAccess
    )
    state = .checking
    return state
  }

  @discardableResult
  public func requestPostEventAccess() -> PermissionState {
    hasRequestedAccess = true
    let current = provider.diagnostics(promptForAccessibility: false)
    diagnostics = PermissionDiagnostics(
      accessibilityTrusted: current.accessibilityTrusted,
      listenEventAccess: current.listenEventAccess,
      postEventAccess:
        current.postEventAccess
        || provider.requestPostEventAccess()
    )
    state = .checking
    return state
  }

  @discardableResult
  public func recordEventTapCreation(succeeded: Bool) -> PermissionState {
    state = succeeded ? .granted : .tapCreationFailed
    return state
  }

  private var hasAllRequiredAccess: Bool {
    diagnostics.accessibilityTrusted
      && diagnostics.listenEventAccess
      && diagnostics.postEventAccess
  }
}
