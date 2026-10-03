import Foundation

/// The exact rule context used by release-time recognition. Evaluating it has no side effects.
public struct GesturePreviewContext: Equatable, Sendable {
  public let mappings: [GestureMapping]
  public let bundleID: String?
  public var matchContext: GestureMatchContext
  public var useSecondaryAction: Bool
  public let configuration: GestureRecognizer.Configuration

  public init(
    mappings: [GestureMapping], bundleID: String?,
    matchContext: GestureMatchContext = GestureMatchContext(),
    useSecondaryAction: Bool = false,
    configuration: GestureRecognizer.Configuration = GestureRecognizer.Configuration()
  ) {
    self.mappings = mappings
    self.bundleID = bundleID
    self.matchContext = matchContext
    self.useSecondaryAction = useSecondaryAction
    self.configuration = configuration
  }

  public func match(_ points: [GesturePoint]) -> GestureSuggestion? {
    guard let template = try? GestureNormalizer().normalize(points),
      case .matched(let match) = GestureRecognizer(configuration: configuration).recognize(
        template, mappings: mappings, frontmostBundleID: bundleID,
        inputDevice: matchContext.inputDevice, matchContext: matchContext,
        useSecondaryAction: useSecondaryAction
      ), match.action.performsAction
    else { return nil }
    return GestureSuggestion(
      mappingID: match.mappingID, name: match.request.mappingName, distance: match.distance)
  }
}

public struct GestureSuggestion: Codable, Equatable, Identifiable, Sendable {
  public let mappingID: UUID
  public let name: String
  public let distance: Float
  public var id: UUID { mappingID }

  public init(mappingID: UUID, name: String, distance: Float = 0) {
    self.mappingID = mappingID
    self.name = name
    self.distance = distance
  }
}

/// Bounded metadata only. Never retains the user's raw stroke.
public struct GestureDiagnosticDetail: Codable, Equatable, Sendable {
  public enum Reason: String, Codable, Sendable {
    case matched, strokeTooShort, invalidStroke, noMatch, ambiguous
    case applicationScope, trigger, conditions, actionFailed
  }

  public let reason: Reason
  public let suggestions: [GestureSuggestion]
  public let applicationBundleID: String?
  public let actionFailure: ActionExecutionFailure?

  public init(
    reason: Reason,
    suggestions: [GestureSuggestion] = [],
    applicationBundleID: String? = nil,
    actionFailure: ActionExecutionFailure? = nil
  ) {
    self.reason = reason
    self.suggestions = Array(suggestions.prefix(3))
    self.applicationBundleID = applicationBundleID
    self.actionFailure = actionFailure
  }

  public var outcome: GestureDiagnosticRecord.Outcome {
    switch reason {
    case .matched: .executed
    case .ambiguous: .ambiguous
    case .actionFailed: .actionFailed
    default: .noMatch
    }
  }
}

public struct GestureReferenceEntry: Identifiable, Sendable {
  public let mapping: GestureMapping
  public let requiresConditions: Bool
  public let overriddenBy: GestureSuggestion?
  public var id: UUID { mapping.id }
}

public enum GestureAssistance {
  public static func diagnose(
    _ points: [GesturePoint],
    snapshot: CompiledMappingSnapshot,
    bundleID: String?,
    trigger: GestureTriggerButton,
    defaultTrigger: GestureTriggerButton,
    context: GestureMatchContext = GestureMatchContext(),
    recognizer: GestureRecognizer = GestureRecognizer(),
    useSecondaryAction: Bool = false
  ) -> GestureDiagnosticDetail {
    let gesture: GestureTemplate
    do {
      gesture = try GestureNormalizer().normalize(points)
    } catch {
      let tooShort =
        switch error {
        case GestureNormalizer.NormalizationError.pathTooShort,
          GestureNormalizer.NormalizationError.insufficientPoints:
          true
        default: false
        }
      return GestureDiagnosticDetail(
        reason: tooShort ? .strokeTooShort : .invalidStroke,
        applicationBundleID: bundleID
      )
    }

    let mappings = snapshot.mappings.filter {
      $0.isEnabled && $0.action.isValid && $0.inputVariant == .draw
    }
    let eligible = mappings.filter {
      ($0.triggerButton ?? defaultTrigger) == trigger
        && $0.appScope.includes(bundleID: bundleID)
        && $0.deviceScope.includes(context.inputDevice)
        && $0.contextCondition.matches(context)
        && Set($0.requiredChordButtons).isSubset(of: context.heldButtons)
    }
    let decision = recognizer.recognize(
      gesture, mappings: eligible, frontmostBundleID: bundleID,
      inputDevice: context.inputDevice, matchContext: context,
      useSecondaryAction: useSecondaryAction
    )
    if case .matched(let match) = decision {
      return GestureDiagnosticDetail(
        reason: .matched,
        suggestions: [
          GestureSuggestion(
            mappingID: match.mappingID, name: match.request.mappingName,
            distance: match.distance
          )
        ], applicationBundleID: bundleID
      )
    }

    var ranked = rankedMappings(gesture, mappings: eligible, recognizer: recognizer)
    if case .ambiguous = decision {
      // Match the engine's specificity rule, so the named conflicts are the
      // candidates that actually caused rejection, not an overridden global rule.
      if let nearest = ranked.first {
        let specificity = ranked.filter {
          $0.1 <= recognizer.configuration.acceptanceThreshold
            && $0.1 - nearest.1 < recognizer.configuration.ambiguityMargin
        }.map {
          recognizer.specificity(of: $0.0, for: bundleID, inputDevice: context.inputDevice)
        }.max()
        ranked = ranked.filter {
          recognizer.specificity(of: $0.0, for: bundleID, inputDevice: context.inputDevice)
            == specificity
        }
      }
      return GestureDiagnosticDetail(
        reason: .ambiguous, suggestions: suggestions(ranked),
        applicationBundleID: bundleID
      )
    }

    let eligibleIDs = Set(eligible.map(\.id))
    let blocked = rankedMappings(
      gesture, mappings: mappings.filter { !eligibleIDs.contains($0.id) },
      recognizer: recognizer
    )
    if let (mapping, distance) = blocked.first,
      distance <= recognizer.configuration.acceptanceThreshold
    {
      let reason: GestureDiagnosticDetail.Reason =
        !mapping.appScope.includes(bundleID: bundleID)
        ? .applicationScope
        : (mapping.triggerButton ?? defaultTrigger) != trigger ? .trigger : .conditions
      return GestureDiagnosticDetail(
        reason: reason, suggestions: suggestions(Array(blocked.prefix(1))),
        applicationBundleID: bundleID
      )
    }
    return GestureDiagnosticDetail(
      reason: .noMatch, suggestions: suggestions(ranked), applicationBundleID: bundleID
    )
  }

  public static func reference(
    snapshot: CompiledMappingSnapshot,
    bundleID: String?,
    defaultTrigger: GestureTriggerButton,
    context: GestureMatchContext = GestureMatchContext(),
    exclusions: Set<ApplicationExclusionRule> = [],
    trackpadGestureEnabled: Bool = true,
    recognizer: GestureRecognizer = GestureRecognizer()
  ) -> [GestureReferenceEntry] {
    let visible = snapshot.mappings.filter { mapping in
      mapping.isEnabled && mapping.action.isValid
        && (trackpadGestureEnabled || (mapping.triggerButton ?? defaultTrigger) != .trackpad)
        && mapping.appScope.includes(bundleID: bundleID)
        && !exclusions.contains {
          $0.bundleIdentifier == bundleID
            && ($0.triggerButton == nil
              || $0.triggerButton == (mapping.triggerButton ?? defaultTrigger))
        }
    }.sorted {
      $0.priority == $1.priority ? $0.id.uuidString < $1.id.uuidString : $0.priority < $1.priority
    }
    return visible.map { mapping in
      let trigger = mapping.triggerButton ?? defaultTrigger
      let input = GestureMatchContext(
        inputDevice: trigger == .trackpad ? .trackpad : context.inputDevice,
        modifierFlags: context.modifierFlags, displayID: context.displayID,
        connectedDeviceIdentifiers: context.connectedDeviceIdentifiers,
        heldButtons: context.heldButtons.union([trigger]), inputVariant: mapping.inputVariant
      )
      let conditional =
        !mapping.contextCondition.matches(input)
        || !mapping.deviceScope.includes(input.inputDevice)
        || !Set(mapping.requiredChordButtons).isSubset(of: input.heldButtons)
      let competing = snapshot.mappings(for: trigger, default: defaultTrigger)
      if !mapping.inputVariant.requiresDrawnGesture {
        let request =
          conditional
          ? nil
          : snapshot.directActionRequest(
            for: bundleID, triggerButton: trigger, default: defaultTrigger, context: input
          )
        let winner = request.flatMap { request -> GestureSuggestion? in
          guard request.mappingID != mapping.id else { return nil }
          return GestureSuggestion(mappingID: request.mappingID, name: request.mappingName)
        }
        return GestureReferenceEntry(
          mapping: mapping, requiresConditions: conditional, overriddenBy: winner)
      }
      let winners: [GestureSuggestion] =
        conditional
        ? []
        : mapping.templates.compactMap { template in
          guard
            case .matched(let match) = recognizer.recognize(
              template, mappings: competing, frontmostBundleID: bundleID,
              inputDevice: input.inputDevice, matchContext: input
            )
          else { return nil }
          let request = match.request
          guard request.mappingID != mapping.id else { return nil }
          return GestureSuggestion(mappingID: request.mappingID, name: request.mappingName)
        }
      let overridden =
        !mapping.templates.isEmpty && winners.count == mapping.templates.count
        && Set(winners.map(\.mappingID)).count == 1
      return GestureReferenceEntry(
        mapping: mapping, requiresConditions: conditional,
        overriddenBy: overridden ? winners.first : nil
      )
    }
  }

  public enum SampleError: Error, Equatable {
    case full, invalidStroke, tooDifferent
    case conflict(String)
  }

  public static func addingSample(
    _ points: [GesturePoint], to mapping: GestureMapping,
    mappings: [GestureMapping], defaultTrigger: GestureTriggerButton,
    recognizer: GestureRecognizer = GestureRecognizer()
  ) throws -> [GestureTemplate] {
    guard mapping.templates.count < MappingStoreLimits().maximumTemplatesPerMapping else {
      throw SampleError.full
    }
    guard mapping.inputVariant == .draw,
      let template = try? GestureNormalizer().normalize(points)
    else { throw SampleError.invalidStroke }
    guard
      mapping.templates.contains(where: {
        recognizer.distance(from: template, to: $0) <= recognizer.configuration.acceptanceThreshold
      })
    else { throw SampleError.tooDifferent }
    let competing = mappings.filter {
      $0.id != mapping.id && $0.isEnabled && $0.inputVariant == .draw
        && $0.applicationGroupID == mapping.applicationGroupID
        && $0.appScope.competes(with: mapping.appScope)
        && $0.deviceScope.competes(with: mapping.deviceScope)
        && ($0.triggerButton ?? defaultTrigger) == (mapping.triggerButton ?? defaultTrigger)
        && Set($0.requiredChordButtons) == Set(mapping.requiredChordButtons)
        && $0.contextCondition == mapping.contextCondition
    }
    if let (conflict, distance) = rankedMappings(
      template, mappings: competing, recognizer: recognizer
    ).first,
      distance < GestureTrainingSession.Configuration().conflictThreshold
    {
      throw SampleError.conflict(conflict.name)
    }
    return mapping.templates + [template]
  }

  private static func rankedMappings(
    _ gesture: GestureTemplate, mappings: [GestureMapping], recognizer: GestureRecognizer
  ) -> [(GestureMapping, Float)] {
    mappings.compactMap { mapping in
      guard
        let distance = mapping.templates.map({ recognizer.distance(from: gesture, to: $0) })
          .filter(\.isFinite).min()
      else { return nil }
      return (mapping, distance)
    }.sorted {
      if $0.1 != $1.1 { return $0.1 < $1.1 }
      if $0.0.priority != $1.0.priority { return $0.0.priority < $1.0.priority }
      return $0.0.id.uuidString < $1.0.id.uuidString
    }
  }

  private static func suggestions(_ ranked: [(GestureMapping, Float)]) -> [GestureSuggestion] {
    ranked.prefix(3).map { GestureSuggestion(mappingID: $0.0.id, name: $0.0.name, distance: $0.1) }
  }
}
