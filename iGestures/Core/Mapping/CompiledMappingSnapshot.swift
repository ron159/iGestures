import Foundation

public struct CompiledMappingSnapshot: Sendable {
  public static let empty = CompiledMappingSnapshot(mappings: [])

  public let mappings: [GestureMapping]
  public let namedActions: [NamedGestureAction]
  private let inheritedTriggerMappings: [GestureMapping]
  private let mappingsByTrigger: [GestureTriggerButton: [GestureMapping]]

  public init(mappings: [GestureMapping]) {
    self.init(mappings: mappings, namedActions: [])
  }

  public init(database: GestureDatabase) {
    let namedActionsByID = Dictionary(
      uniqueKeysWithValues: database.namedActions.map { ($0.id, $0) }
    )
    let enabledConfigurationSetIDs = Set(
      database.configurationSets.filter(\.isEnabled).map(\.id)
    )
    let activeMappings = database.mappings.filter { mapping in
      guard let configurationSetID = mapping.configurationSetID else {
        return true
      }
      return enabledConfigurationSetIDs.contains(configurationSetID)
    }
    let compiledMappings = activeMappings.map { mapping in
      var compiled = mapping
      compiled.action =
        Self.expand(
          mapping.action,
          namedActionsByID: namedActionsByID,
          resolving: []
        ) ?? .none
      compiled.secondaryAction = mapping.secondaryAction.flatMap {
        Self.expand(
          $0,
          namedActionsByID: namedActionsByID,
          resolving: []
        )
      }
      return compiled
    }
    let compiledNamedActions = database.namedActions.map { namedAction in
      var compiled = namedAction
      compiled.action =
        namedAction.isEnabled
        ? Self.expand(
          namedAction.action,
          namedActionsByID: namedActionsByID,
          resolving: []
        ) ?? .none
        : .none
      return compiled
    }
    self.init(
      mappings: compiledMappings,
      namedActions: compiledNamedActions
    )
  }

  private init(
    mappings: [GestureMapping],
    namedActions: [NamedGestureAction]
  ) {
    self.mappings = mappings
    self.namedActions = namedActions
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
    default defaultTriggerButton: GestureTriggerButton,
    context: GestureMatchContext? = nil
  ) -> [GestureMapping] {
    var result = mappingsByTrigger[triggerButton] ?? []
    if triggerButton == defaultTriggerButton {
      result.append(contentsOf: inheritedTriggerMappings)
    }
    guard let context else { return result }
    return result.filter { mapping in
      mapping.contextCondition.matches(context)
        && mapping.deviceScope.includes(context.inputDevice)
        && Set(mapping.requiredChordButtons).isSubset(
          of: context.heldButtons
        )
        && Self.variant(mapping.inputVariant, matches: context.inputVariant)
    }
  }

  public func hasApplicableMapping(
    for bundleID: String?,
    triggerButton: GestureTriggerButton,
    default defaultTriggerButton: GestureTriggerButton,
    inputDevice: GestureInputDevice = .mouse(identifier: nil),
    context: GestureMatchContext? = nil
  ) -> Bool {
    let context = context ?? GestureMatchContext(inputDevice: inputDevice)
    return mappings(
      for: triggerButton,
      default: defaultTriggerButton,
      context: context
    ).contains {
      $0.isEnabled
        && $0.action.isValid
        && !$0.templates.isEmpty
        && $0.inputVariant.requiresDrawnGesture
        && $0.appScope.includes(bundleID: bundleID)
    }
  }

  public func hasApplicableMapping(for bundleID: String?) -> Bool {
    hasApplicableMapping(
      for: bundleID,
      triggerButton: .right,
      default: .right
    )
  }

  public func directActionRequest(
    for bundleID: String?,
    triggerButton: GestureTriggerButton,
    default defaultTriggerButton: GestureTriggerButton,
    context: GestureMatchContext
  ) -> ActionRequest? {
    mappings(
      for: triggerButton,
      default: defaultTriggerButton,
      context: context
    )
    .filter {
      $0.isEnabled
        && $0.action.isValid
        && !$0.inputVariant.requiresDrawnGesture
        && $0.appScope.includes(bundleID: bundleID)
    }
    .sorted { $0.priority < $1.priority }
    .first
    .map {
      ActionRequest(
        mappingID: $0.id,
        mappingName: $0.name,
        action: $0.action,
        repeatModeEnabled: $0.repeatModeEnabled
      )
    }
  }

  public func hasDirectAction(
    for bundleID: String?,
    triggerButton: GestureTriggerButton,
    default defaultTriggerButton: GestureTriggerButton,
    context: GestureMatchContext
  ) -> Bool {
    var candidates = mappingsByTrigger[triggerButton] ?? []
    if triggerButton == defaultTriggerButton {
      candidates.append(contentsOf: inheritedTriggerMappings)
    }
    return candidates.contains { mapping in
      mapping.isEnabled
        && mapping.action.isValid
        && !mapping.inputVariant.requiresDrawnGesture
        && mapping.appScope.includes(bundleID: bundleID)
        && mapping.contextCondition.matches(context)
        && mapping.deviceScope.includes(context.inputDevice)
        && Set(mapping.requiredChordButtons).isSubset(
          of: context.heldButtons
        )
        && Self.sameVariantFamily(
          mapping.inputVariant,
          context.inputVariant
        )
    }
  }

  public func hasApplicableSecondaryGesture(
    for bundleID: String?,
    inputDevice: GestureInputDevice = .mouse(identifier: nil)
  ) -> Bool {
    mappings.contains {
      $0.isEnabled
        && $0.action.isValid
        && ($0.secondaryAction?.isValid ?? true)
        && !$0.templates.isEmpty
        && $0.inputVariant.requiresDrawnGesture
        && $0.appScope.includes(bundleID: bundleID)
        && $0.deviceScope.includes(inputDevice)
    }
  }

  public func namedAction(named name: String) -> NamedGestureAction? {
    namedActions.first {
      $0.name.compare(
        name,
        options: [.caseInsensitive, .diacriticInsensitive]
      ) == .orderedSame
    }
  }

  private static func variant(
    _ expected: GestureInputVariant,
    matches actual: GestureInputVariant
  ) -> Bool {
    switch (expected, actual) {
    case (.draw, .draw):
      return true
    case (
      .doubleClick(let maximumInterval),
      .doubleClick(let actualInterval)
    ):
      return actualInterval <= maximumInterval
    case (
      .longPress(let minimumDuration),
      .longPress(let actualDuration)
    ):
      return actualDuration >= minimumDuration
    case (
      .scrollWheel(let expectedDirection),
      .scrollWheel(let actualDirection)
    ):
      return expectedDirection == .either
        || expectedDirection == actualDirection
    default:
      return false
    }
  }

  private static func sameVariantFamily(
    _ left: GestureInputVariant,
    _ right: GestureInputVariant
  ) -> Bool {
    switch (left, right) {
    case (.draw, .draw), (.doubleClick, .doubleClick),
      (.longPress, .longPress), (.scrollWheel, .scrollWheel):
      return true
    default:
      return false
    }
  }

  private static func expand(
    _ action: GestureAction,
    namedActionsByID: [UUID: NamedGestureAction],
    resolving: Set<UUID>
  ) -> GestureAction? {
    switch action {
    case .namedAction(let id):
      guard !resolving.contains(id),
        let namedAction = namedActionsByID[id],
        namedAction.isEnabled
      else {
        return nil
      }
      var nextResolving = resolving
      nextResolving.insert(id)
      return expand(
        namedAction.action,
        namedActionsByID: namedActionsByID,
        resolving: nextResolving
      )
    case .sequence(var sequence):
      var steps: [GestureActionStep] = []
      steps.reserveCapacity(sequence.steps.count)
      for step in sequence.steps {
        guard
          let expanded = expand(
            step.action,
            namedActionsByID: namedActionsByID,
            resolving: resolving
          )
        else {
          return nil
        }
        steps.append(
          GestureActionStep(
            action: expanded,
            delayAfter: step.delayAfter
          )
        )
      }
      sequence.steps = steps
      if case .fallback(let fallback) = sequence.failurePolicy {
        guard
          let expandedFallback = expand(
            fallback,
            namedActionsByID: namedActionsByID,
            resolving: resolving
          )
        else {
          return nil
        }
        sequence.failurePolicy = .fallback(expandedFallback)
      }
      return .sequence(sequence)
    default:
      return action
    }
  }
}
