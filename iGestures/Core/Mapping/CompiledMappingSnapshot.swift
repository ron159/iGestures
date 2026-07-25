public struct CompiledMappingSnapshot: Sendable {
  public static let empty = CompiledMappingSnapshot(mappings: [])

  public let mappings: [GestureMapping]

  public init(mappings: [GestureMapping]) {
    self.mappings = mappings
  }

  public func hasApplicableMapping(for bundleID: String?) -> Bool {
    mappings.contains {
      $0.isEnabled
        && $0.shortcut.isValid
        && !$0.templates.isEmpty
        && $0.appScope.includes(bundleID: bundleID)
    }
  }
}
