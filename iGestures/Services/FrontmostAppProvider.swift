import AppKit

public protocol FrontmostAppProviding: Sendable {
  func currentBundleID(at screenPoint: CGPoint?) -> String?
}

public struct SystemFrontmostAppProvider: FrontmostAppProviding {
  public init() {}

  public func currentBundleID(at screenPoint: CGPoint?) -> String? {
    if let screenPoint,
      let ownerPID = frontmostWindowOwnerPID(at: screenPoint),
      let bundleID = NSRunningApplication(
        processIdentifier: ownerPID
      )?.bundleIdentifier
    {
      return bundleID
    }
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  }

  private func frontmostWindowOwnerPID(at point: CGPoint) -> pid_t? {
    guard
      let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return nil
    }
    return FrontmostWindowResolver.ownerPID(
      at: point,
      windows: windowInfo.compactMap(ApplicationWindowDescriptor.init)
    )
  }
}

struct ApplicationWindowDescriptor: Equatable {
  let bounds: CGRect
  let layer: Int
  let alpha: Double
  let ownerPID: pid_t

  init(
    bounds: CGRect,
    layer: Int = 0,
    alpha: Double = 1,
    ownerPID: pid_t
  ) {
    self.bounds = bounds
    self.layer = layer
    self.alpha = alpha
    self.ownerPID = ownerPID
  }

  init?(windowInfo: [String: Any]) {
    guard
      let bounds = Self.windowBounds(
        from: windowInfo[kCGWindowBounds as String]
      ),
      let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?
        .intValue,
      let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?
        .int32Value
    else {
      return nil
    }
    self.init(
      bounds: bounds,
      layer: layer,
      alpha: (windowInfo[kCGWindowAlpha as String] as? NSNumber)?
        .doubleValue ?? 1,
      ownerPID: ownerPID
    )
  }

  private static func windowBounds(from value: Any?) -> CGRect? {
    guard
      let values = value as? [String: NSNumber],
      let x = values["X"],
      let y = values["Y"],
      let width = values["Width"],
      let height = values["Height"]
    else {
      return nil
    }
    return CGRect(
      x: x.doubleValue,
      y: y.doubleValue,
      width: width.doubleValue,
      height: height.doubleValue
    )
  }
}

enum FrontmostWindowResolver {
  static func ownerPID(
    at point: CGPoint,
    windows: [ApplicationWindowDescriptor]
  ) -> pid_t? {
    windows.first {
      $0.layer == 0
        && $0.alpha > 0
        && $0.bounds.contains(point)
    }?.ownerPID
  }
}
