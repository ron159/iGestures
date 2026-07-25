import AppKit

public protocol FrontmostAppProviding: Sendable {
  func currentBundleID() -> String?
}

public struct SystemFrontmostAppProvider: FrontmostAppProviding {
  public init() {}

  public func currentBundleID() -> String? {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  }
}
