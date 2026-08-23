import Foundation

public struct GestureApplicationGroup:
  Codable,
  Equatable,
  Identifiable,
  Sendable
{
  public let id: UUID
  public var name: String
  public var bundleIdentifiers: [String]

  public init(
    id: UUID = UUID(),
    name: String,
    bundleIdentifiers: [String] = []
  ) {
    self.id = id
    self.name = name
    self.bundleIdentifiers = bundleIdentifiers
  }
}

public struct GestureConfigurationSet:
  Codable,
  Equatable,
  Identifiable,
  Sendable
{
  public let id: UUID
  public var name: String
  public var isEnabled: Bool

  public init(
    id: UUID = UUID(),
    name: String,
    isEnabled: Bool = true
  ) {
    self.id = id
    self.name = name
    self.isEnabled = isEnabled
  }
}

public struct NamedGestureAction:
  Codable,
  Equatable,
  Identifiable,
  Sendable
{
  public let id: UUID
  public var name: String
  public var action: GestureAction
  public var isEnabled: Bool
  public var allowsAppIntent: Bool

  public init(
    id: UUID = UUID(),
    name: String,
    action: GestureAction,
    isEnabled: Bool = true,
    allowsAppIntent: Bool = false
  ) {
    self.id = id
    self.name = name
    self.action = action
    self.isEnabled = isEnabled
    self.allowsAppIntent = allowsAppIntent
  }
}

public struct GestureDatabase: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 5
  public static let empty = GestureDatabase(
    schemaVersion: currentSchemaVersion,
    mappings: [],
    applicationGroups: [],
    managedApplicationBundleIdentifiers: [],
    configurationSets: [],
    namedActions: []
  )

  public let schemaVersion: Int
  public var mappings: [GestureMapping]
  public var applicationGroups: [GestureApplicationGroup]
  public var managedApplicationBundleIdentifiers: [String]
  public var configurationSets: [GestureConfigurationSet]
  public var namedActions: [NamedGestureAction]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    mappings: [GestureMapping],
    applicationGroups: [GestureApplicationGroup] = [],
    managedApplicationBundleIdentifiers: [String] = [],
    configurationSets: [GestureConfigurationSet] = [],
    namedActions: [NamedGestureAction] = []
  ) {
    self.schemaVersion = schemaVersion
    self.mappings = mappings
    self.applicationGroups = applicationGroups
    self.managedApplicationBundleIdentifiers =
      managedApplicationBundleIdentifiers
    self.configurationSets = configurationSets
    self.namedActions = namedActions
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case mappings
    case applicationGroups
    case managedApplicationBundleIdentifiers
    case configurationSets
    case namedActions
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedVersion = try container.decode(
      Int.self,
      forKey: .schemaVersion
    )
    switch decodedVersion {
    case 1, 2, 3, 4:
      schemaVersion = Self.currentSchemaVersion
    default:
      schemaVersion = decodedVersion
    }
    mappings = try container.decode(
      [GestureMapping].self,
      forKey: .mappings
    )
    applicationGroups =
      try container.decodeIfPresent(
        [GestureApplicationGroup].self,
        forKey: .applicationGroups
      ) ?? []
    managedApplicationBundleIdentifiers =
      try container.decodeIfPresent(
        [String].self,
        forKey: .managedApplicationBundleIdentifiers
      ) ?? []
    configurationSets =
      try container.decodeIfPresent(
        [GestureConfigurationSet].self,
        forKey: .configurationSets
      ) ?? []
    namedActions =
      try container.decodeIfPresent(
        [NamedGestureAction].self,
        forKey: .namedActions
      ) ?? []
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(mappings, forKey: .mappings)
    try container.encode(
      applicationGroups,
      forKey: .applicationGroups
    )
    try container.encode(
      managedApplicationBundleIdentifiers,
      forKey: .managedApplicationBundleIdentifiers
    )
    try container.encode(configurationSets, forKey: .configurationSets)
    try container.encode(namedActions, forKey: .namedActions)
  }

  public var compiledSnapshot: CompiledMappingSnapshot {
    CompiledMappingSnapshot(database: self)
  }
}
