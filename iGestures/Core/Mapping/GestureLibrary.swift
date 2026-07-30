import Foundation

public struct GestureMappingDraft: Sendable {
  public var name: String
  public var templates: [GestureTemplate]
  public var action: GestureAction
  public var secondaryAction: GestureAction?
  public var appScope: AppScope
  public var triggerButton: GestureTriggerButton?
  public var category: String?
  public var applicationGroupID: UUID?
  public var repeatModeEnabled: Bool
  public var deviceScope: InputDeviceScope
  public var isEnabled: Bool

  public init(
    name: String,
    templates: [GestureTemplate],
    action: GestureAction,
    secondaryAction: GestureAction? = nil,
    appScope: AppScope = .all,
    triggerButton: GestureTriggerButton? = nil,
    category: String? = nil,
    applicationGroupID: UUID? = nil,
    repeatModeEnabled: Bool = false,
    deviceScope: InputDeviceScope = .any,
    isEnabled: Bool = true
  ) {
    self.name = name
    self.templates = templates
    self.action = action
    self.secondaryAction = secondaryAction
    self.appScope = appScope
    self.triggerButton = triggerButton
    self.category = category
    self.applicationGroupID = applicationGroupID
    self.repeatModeEnabled = repeatModeEnabled
    self.deviceScope = deviceScope
    self.isEnabled = isEnabled
  }

  public init(
    name: String,
    templates: [GestureTemplate],
    shortcut: KeyboardShortcut,
    secondaryAction: GestureAction? = nil,
    appScope: AppScope = .all,
    triggerButton: GestureTriggerButton? = nil,
    category: String? = nil,
    applicationGroupID: UUID? = nil,
    repeatModeEnabled: Bool = false,
    deviceScope: InputDeviceScope = .any,
    isEnabled: Bool = true
  ) {
    self.init(
      name: name,
      templates: templates,
      action: .keyboardShortcut(shortcut),
      secondaryAction: secondaryAction,
      appScope: appScope,
      triggerButton: triggerButton,
      category: category,
      applicationGroupID: applicationGroupID,
      repeatModeEnabled: repeatModeEnabled,
      deviceScope: deviceScope,
      isEnabled: isEnabled
    )
  }
}

public enum GestureLibraryError: Error, Equatable, Sendable {
  case mappingNotFound
  case indexOutOfBounds
  case missingAction
}

public struct GestureLibrary: Sendable {
  public private(set) var database: GestureDatabase

  public init(database: GestureDatabase = .empty) {
    self.database = database
    normalizePriorities()
  }

  @discardableResult
  public mutating func create(
    _ draft: GestureMappingDraft,
    id: UUID = UUID()
  ) -> UUID {
    database.mappings.append(
      GestureMapping(
        id: id,
        name: draft.name,
        isEnabled: draft.isEnabled,
        templates: draft.templates,
        action: draft.action,
        secondaryAction: draft.secondaryAction,
        appScope: draft.appScope,
        triggerButton: draft.triggerButton,
        category: draft.category,
        applicationGroupID: draft.applicationGroupID,
        repeatModeEnabled: draft.repeatModeEnabled,
        deviceScope: draft.deviceScope,
        priority: database.mappings.count
      )
    )
    return id
  }

  public mutating func rename(
    id: UUID,
    to name: String
  ) throws {
    try update(id: id) {
      $0.name = name
    }
  }

  public mutating func update(
    id: UUID,
    with draft: GestureMappingDraft
  ) throws {
    try update(id: id) {
      $0.name = draft.name
      $0.templates = draft.templates
      $0.action = draft.action
      $0.secondaryAction = draft.secondaryAction
      $0.appScope = draft.appScope
      $0.triggerButton = draft.triggerButton
      $0.category = draft.category
      $0.applicationGroupID = draft.applicationGroupID
      $0.repeatModeEnabled = draft.repeatModeEnabled
      $0.deviceScope = draft.deviceScope
      $0.isEnabled =
        draft.isEnabled
        && draft.action.isValid
        && (draft.secondaryAction?.isValid ?? true)
    }
  }

  public mutating func setEnabled(
    id: UUID,
    _ isEnabled: Bool
  ) throws {
    try update(id: id) {
      if isEnabled
        && (!$0.action.isValid
          || !($0.secondaryAction?.isValid ?? true))
      {
        throw GestureLibraryError.missingAction
      }
      $0.isEnabled = isEnabled
    }
  }

  public mutating func setShortcut(
    id: UUID,
    _ shortcut: KeyboardShortcut
  ) throws {
    try update(id: id) {
      $0.shortcut = shortcut
      if !shortcut.isValid {
        $0.isEnabled = false
      }
    }
  }

  public mutating func setAction(
    id: UUID,
    _ action: GestureAction
  ) throws {
    try update(id: id) {
      $0.action = action
      if !action.isValid {
        $0.isEnabled = false
      }
    }
  }

  public mutating func setSecondaryAction(
    id: UUID,
    _ action: GestureAction?
  ) throws {
    try update(id: id) {
      $0.secondaryAction = action
      if let action, !action.isValid {
        $0.isEnabled = false
      }
    }
  }

  public mutating func setAppScope(
    id: UUID,
    _ appScope: AppScope
  ) throws {
    try update(id: id) {
      $0.appScope = appScope
    }
  }

  public mutating func setApplicationGroup(
    id: UUID,
    _ applicationGroupID: UUID?
  ) throws {
    try update(id: id) {
      $0.applicationGroupID = applicationGroupID
    }
  }

  public mutating func setTriggerButton(
    id: UUID,
    _ triggerButton: GestureTriggerButton?
  ) throws {
    try update(id: id) {
      $0.triggerButton = triggerButton
    }
  }

  public mutating func setCategory(
    id: UUID,
    _ category: String?
  ) throws {
    try update(id: id) {
      let trimmed = category?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      $0.category =
        trimmed?.isEmpty == false
        ? trimmed
        : nil
    }
  }

  public mutating func setRepeatModeEnabled(
    id: UUID,
    _ enabled: Bool
  ) throws {
    try update(id: id) {
      $0.repeatModeEnabled = enabled
    }
  }

  public mutating func setDeviceScope(
    id: UUID,
    _ scope: InputDeviceScope
  ) throws {
    try update(id: id) {
      $0.deviceScope = scope
    }
  }

  public mutating func replaceTemplates(
    id: UUID,
    with templates: [GestureTemplate]
  ) throws {
    try update(id: id) {
      $0.templates = templates
    }
  }

  public mutating func delete(id: UUID) throws {
    guard
      let index = database.mappings.firstIndex(where: {
        $0.id == id
      })
    else {
      throw GestureLibraryError.mappingNotFound
    }
    database.mappings.remove(at: index)
    normalizePriorities()
  }

  public mutating func move(
    from sourceIndex: Int,
    to destinationIndex: Int
  ) throws {
    guard database.mappings.indices.contains(sourceIndex),
      destinationIndex >= 0,
      destinationIndex < database.mappings.count
    else {
      throw GestureLibraryError.indexOutOfBounds
    }
    guard sourceIndex != destinationIndex else { return }

    let mapping = database.mappings.remove(at: sourceIndex)
    database.mappings.insert(mapping, at: destinationIndex)
    normalizePriorities()
  }

  private mutating func update(
    id: UUID,
    mutation: (inout GestureMapping) throws -> Void
  ) throws {
    guard
      let index = database.mappings.firstIndex(where: {
        $0.id == id
      })
    else {
      throw GestureLibraryError.mappingNotFound
    }
    try mutation(&database.mappings[index])
  }

  private mutating func normalizePriorities() {
    for index in database.mappings.indices {
      database.mappings[index].priority = index
    }
  }
}

public struct GesturePreset: Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let template: GestureTemplate
  public let action: GestureAction

  public init(
    id: UUID,
    name: String,
    template: GestureTemplate,
    action: GestureAction
  ) {
    self.id = id
    self.name = name
    self.template = template
    self.action = action
  }

  public var draft: GestureMappingDraft {
    GestureMappingDraft(
      name: name,
      templates: [template],
      action: action
    )
  }
}

public enum GesturePresetLibrary {
  public static let builtIn: [GesturePreset] = [
    make(
      id: "00000000-0000-0000-0001-000000000001",
      name: String(localized: "Back"),
      points: line(from: (160, 40), to: (0, 40)),
      action: .keyboardShortcut(
        KeyboardShortcut(keyCode: 33, modifiers: 0x10_0000)
      )
    ),
    make(
      id: "00000000-0000-0000-0001-000000000002",
      name: String(localized: "Forward"),
      points: line(from: (0, 40), to: (160, 40)),
      action: .keyboardShortcut(
        KeyboardShortcut(keyCode: 30, modifiers: 0x10_0000)
      )
    ),
    make(
      id: "00000000-0000-0000-0001-000000000003",
      name: String(localized: "Close Tab"),
      points: polyline([(0, 0), (80, 80), (160, 0)]),
      action: .keyboardShortcut(
        KeyboardShortcut(keyCode: 13, modifiers: 0x10_0000)
      )
    ),
    make(
      id: "00000000-0000-0000-0001-000000000004",
      name: String(localized: "New Tab"),
      points: polyline([(0, 80), (80, 0), (160, 80)]),
      action: .keyboardShortcut(
        KeyboardShortcut(keyCode: 17, modifiers: 0x10_0000)
      )
    ),
    make(
      id: "00000000-0000-0000-0001-000000000005",
      name: String(localized: "Refresh"),
      points: circle(),
      action: .keyboardShortcut(
        KeyboardShortcut(keyCode: 15, modifiers: 0x10_0000)
      )
    ),
    make(
      id: "00000000-0000-0000-0001-000000000006",
      name: String(localized: "Mission Control"),
      points: line(from: (80, 160), to: (80, 0)),
      action: .system(.missionControl)
    ),
    make(
      id: "00000000-0000-0000-0001-000000000007",
      name: String(localized: "Show Desktop"),
      points: line(from: (80, 0), to: (80, 160)),
      action: .system(.showDesktop)
    ),
    make(
      id: "00000000-0000-0000-0001-000000000008",
      name: String(localized: "Application Switcher"),
      points: polyline([(0, 0), (80, 60), (0, 120)]),
      action: .system(.appSwitcher)
    ),
  ].compactMap { $0 }

  private static func make(
    id: String,
    name: String,
    points: [GesturePoint],
    action: GestureAction
  ) -> GesturePreset? {
    guard let id = UUID(uuidString: id),
      let template = try? GestureNormalizer().normalize(points)
    else {
      return nil
    }
    return GesturePreset(
      id: id,
      name: name,
      template: template,
      action: action
    )
  }

  private static func line(
    from start: (Float, Float),
    to end: (Float, Float)
  ) -> [GesturePoint] {
    (0..<80).map { index in
      let progress = Float(index) / 79
      return GesturePoint(
        x: start.0 + ((end.0 - start.0) * progress),
        y: start.1 + ((end.1 - start.1) * progress)
      )
    }
  }

  private static func polyline(
    _ vertices: [(Float, Float)]
  ) -> [GesturePoint] {
    guard vertices.count > 1 else { return [] }
    let segmentCount = vertices.count - 1
    return (0..<96).map { index in
      let progress =
        (Float(index) / 95) * Float(segmentCount)
      let segment = min(
        segmentCount - 1,
        Int(progress.rounded(.down))
      )
      let local = progress - Float(segment)
      return GesturePoint(
        x:
          vertices[segment].0
          + ((vertices[segment + 1].0 - vertices[segment].0)
            * local),
        y:
          vertices[segment].1
          + ((vertices[segment + 1].1 - vertices[segment].1)
            * local)
      )
    }
  }

  private static func circle() -> [GesturePoint] {
    (0..<96).map { index in
      let angle = (Float(index) / 95) * (.pi * 2)
      return GesturePoint(
        x: 80 + (cosf(angle) * 70),
        y: 80 + (sinf(angle) * 70)
      )
    }
  }
}
