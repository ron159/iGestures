import Foundation

public struct KeyboardShortcut: Codable, Hashable, Sendable {
  public let keyCode: UInt16
  public let modifiers: UInt64

  public init(keyCode: UInt16, modifiers: UInt64) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  public var isValid: Bool {
    keyCode != UInt16.max
  }
}

public enum AppScope: Codable, Hashable, Sendable {
  case all
  case only([String])
  case allExcept([String])

  private enum CodingKeys: String, CodingKey {
    case type
    case bundleIDs
  }

  private enum ScopeType: String, Codable {
    case all
    case only
    case allExcept
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(ScopeType.self, forKey: .type)
    switch type {
    case .all:
      self = .all
    case .only:
      self = .only(
        try container.decode([String].self, forKey: .bundleIDs)
      )
    case .allExcept:
      self = .allExcept(
        try container.decode([String].self, forKey: .bundleIDs)
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .all:
      try container.encode(ScopeType.all, forKey: .type)
    case .only(let bundleIDs):
      try container.encode(ScopeType.only, forKey: .type)
      try container.encode(bundleIDs, forKey: .bundleIDs)
    case .allExcept(let bundleIDs):
      try container.encode(ScopeType.allExcept, forKey: .type)
      try container.encode(bundleIDs, forKey: .bundleIDs)
    }
  }

  public func includes(bundleID: String?) -> Bool {
    switch self {
    case .all:
      return true
    case .only(let bundleIDs):
      guard let bundleID else { return false }
      return bundleIDs.contains(bundleID)
    case .allExcept(let bundleIDs):
      guard let bundleID else { return false }
      return !bundleIDs.contains(bundleID)
    }
  }
}

public struct GestureMapping: Codable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var name: String
  public var isEnabled: Bool
  public var templates: [GestureTemplate]
  public var shortcut: KeyboardShortcut
  public var appScope: AppScope
  public var priority: Int

  public init(
    id: UUID = UUID(),
    name: String,
    isEnabled: Bool = true,
    templates: [GestureTemplate],
    shortcut: KeyboardShortcut,
    appScope: AppScope = .all,
    priority: Int = 0
  ) {
    self.id = id
    self.name = name
    self.isEnabled = isEnabled
    self.templates = templates
    self.shortcut = shortcut
    self.appScope = appScope
    self.priority = priority
  }
}
