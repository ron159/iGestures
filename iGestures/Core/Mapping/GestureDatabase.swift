public struct GestureDatabase: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public static let empty = GestureDatabase(
    schemaVersion: currentSchemaVersion,
    mappings: []
  )

  public let schemaVersion: Int
  public var mappings: [GestureMapping]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    mappings: [GestureMapping]
  ) {
    self.schemaVersion = schemaVersion
    self.mappings = mappings
  }

  public var compiledSnapshot: CompiledMappingSnapshot {
    CompiledMappingSnapshot(mappings: mappings)
  }
}
