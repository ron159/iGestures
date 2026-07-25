import Foundation

public struct GestureMappingDraft: Sendable {
  public var name: String
  public var templates: [GestureTemplate]
  public var shortcut: KeyboardShortcut
  public var appScope: AppScope
  public var isEnabled: Bool

  public init(
    name: String,
    templates: [GestureTemplate],
    shortcut: KeyboardShortcut,
    appScope: AppScope = .all,
    isEnabled: Bool = true
  ) {
    self.name = name
    self.templates = templates
    self.shortcut = shortcut
    self.appScope = appScope
    self.isEnabled = isEnabled
  }
}

public enum GestureLibraryError: Error, Equatable, Sendable {
  case mappingNotFound
  case indexOutOfBounds
  case missingShortcut
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
        shortcut: draft.shortcut,
        appScope: draft.appScope,
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
      $0.shortcut = draft.shortcut
      $0.appScope = draft.appScope
      $0.isEnabled = draft.isEnabled && draft.shortcut.isValid
    }
  }

  public mutating func setEnabled(
    id: UUID,
    _ isEnabled: Bool
  ) throws {
    try update(id: id) {
      if isEnabled && !$0.shortcut.isValid {
        throw GestureLibraryError.missingShortcut
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

  public mutating func setAppScope(
    id: UUID,
    _ appScope: AppScope
  ) throws {
    try update(id: id) {
      $0.appScope = appScope
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
