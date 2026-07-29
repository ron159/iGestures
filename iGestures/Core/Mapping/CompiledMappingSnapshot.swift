public struct CompiledMappingSnapshot: Sendable {
  public static let empty = CompiledMappingSnapshot(mappings: [])

  public let mappings: [GestureMapping]
  private let inheritedTriggerMappings: [GestureMapping]
  private let mappingsByTrigger: [GestureTriggerButton: [GestureMapping]]
  private let compoundBindings: [CompoundGestureBinding]

  public init(
    mappings: [GestureMapping],
    compoundBindings: [CompoundGestureBinding] = []
  ) {
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
    self.compoundBindings = compoundBindings
  }

  public func compoundAction(
    for input: CompoundGestureInput,
    bundleID: String?
  ) -> ActionRequest? {
    let applicable = compoundBindings.filter {
      $0.isEnabled
        && $0.action.isValid
        && $0.input == input
        && $0.appScope.includes(bundleID: bundleID)
    }
    let specific = applicable.filter {
      $0.appScope.isApplicationSpecific(for: bundleID)
    }
    let candidates = specific.isEmpty ? applicable : specific
    guard
      let binding = candidates.min(by: {
        if $0.priority != $1.priority {
          return $0.priority < $1.priority
        }
        return $0.id.uuidString < $1.id.uuidString
      })
    else {
      return nil
    }
    return ActionRequest(
      mappingID: binding.id,
      mappingName: binding.name,
      action: binding.action
    )
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
}
