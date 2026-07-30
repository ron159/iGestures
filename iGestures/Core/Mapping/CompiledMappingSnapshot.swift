public struct CompiledMappingSnapshot: Sendable {
  public static let empty = CompiledMappingSnapshot(mappings: [])

  public let mappings: [GestureMapping]
  private let inheritedTriggerMappings: [GestureMapping]
  private let mappingsByTrigger: [GestureTriggerButton: [GestureMapping]]

  public init(mappings: [GestureMapping]) {
    self.mappings = mappings
    inheritedTriggerMappings = mappings.filter {
      $0.triggerButton == nil
    }
    mappingsByTrigger = Dictionary(
      grouping: mappings.compactMap { mapping in
        mapping.triggerButton.map { ($0, mapping) }
      },
      by: \.0
    )
    .mapValues { $0.map(\.1) }
  }

  public func mappings(
    for triggerButton: GestureTriggerButton,
    default defaultTriggerButton: GestureTriggerButton
  ) -> [GestureMapping] {
    var result = mappingsByTrigger[triggerButton] ?? []
    if triggerButton == defaultTriggerButton {
      result.append(contentsOf: inheritedTriggerMappings)
    }
    return result
  }

  public func hasApplicableMapping(
    for bundleID: String?,
    triggerButton: GestureTriggerButton,
    default defaultTriggerButton: GestureTriggerButton,
    inputDevice: GestureInputDevice =
      .mouse(identifier: nil)
  ) -> Bool {
    mappings(
      for: triggerButton,
      default: defaultTriggerButton
    ).contains {
      $0.isEnabled
        && $0.action.isValid
        && !$0.templates.isEmpty
        && $0.appScope.includes(bundleID: bundleID)
        && $0.deviceScope.includes(inputDevice)
    }
  }

  public func hasApplicableMapping(for bundleID: String?) -> Bool {
    hasApplicableMapping(
      for: bundleID,
      triggerButton: .right,
      default: .right
    )
  }

  public func hasApplicableSecondaryAction(
    for bundleID: String?,
    inputDevice: GestureInputDevice = .mouse(identifier: nil)
  ) -> Bool {
    mappings.contains {
      $0.isEnabled
        && $0.action.isValid
        && ($0.secondaryAction?.isValid ?? false)
        && !$0.templates.isEmpty
        && $0.appScope.includes(bundleID: bundleID)
        && $0.deviceScope.includes(inputDevice)
    }
  }
}
