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

public struct GestureDatabase: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 4
  public static let empty = GestureDatabase(
    schemaVersion: currentSchemaVersion,
    mappings: [],
    applicationGroups: [],
    managedApplicationBundleIdentifiers: []
  )

  public let schemaVersion: Int
  public var mappings: [GestureMapping]
  public var applicationGroups: [GestureApplicationGroup]
  public var managedApplicationBundleIdentifiers: [String]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    mappings: [GestureMapping],
    applicationGroups: [GestureApplicationGroup] = [],
    managedApplicationBundleIdentifiers: [String] = []
  ) {
    self.schemaVersion = schemaVersion
    self.mappings = mappings
    self.applicationGroups = applicationGroups
    self.managedApplicationBundleIdentifiers =
      managedApplicationBundleIdentifiers
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case mappings
    case applicationGroups
    case managedApplicationBundleIdentifiers
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedVersion = try container.decode(
      Int.self,
      forKey: .schemaVersion
    )
    switch decodedVersion {
    case 1, 2, 3:
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
  }

  public var compiledSnapshot: CompiledMappingSnapshot {
    CompiledMappingSnapshot(mappings: mappings)
  }
}
