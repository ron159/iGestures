import Foundation

public struct GestureDatabase: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 2
  public static let empty = GestureDatabase(
    schemaVersion: currentSchemaVersion,
    mappings: [],
    compoundBindings: []
  )

  public let schemaVersion: Int
  public var mappings: [GestureMapping]
  public var compoundBindings: [CompoundGestureBinding]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    mappings: [GestureMapping],
    compoundBindings: [CompoundGestureBinding] = []
  ) {
    self.schemaVersion = schemaVersion
    self.mappings = mappings
    self.compoundBindings = compoundBindings
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case mappings
    case compoundBindings
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedVersion = try container.decode(
      Int.self,
      forKey: .schemaVersion
    )
    schemaVersion =
      decodedVersion == 1
      ? Self.currentSchemaVersion
      : decodedVersion
    mappings = try container.decode(
      [GestureMapping].self,
      forKey: .mappings
    )
    compoundBindings =
      try container.decodeIfPresent(
        [CompoundGestureBinding].self,
        forKey: .compoundBindings
      ) ?? []
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(mappings, forKey: .mappings)
    try container.encode(
      compoundBindings,
      forKey: .compoundBindings
    )
  }

  public var compiledSnapshot: CompiledMappingSnapshot {
    CompiledMappingSnapshot(
      mappings: mappings,
      compoundBindings: compoundBindings
    )
  }
}

public enum CompoundScrollDirection: String, Codable, Sendable {
  case up
  case down
}

public enum CompoundGestureInput: Codable, Hashable, Sendable {
  case rocker(
    first: GestureTriggerButton,
    second: GestureTriggerButton
  )
  case wheel(
    trigger: GestureTriggerButton,
    direction: CompoundScrollDirection
  )

  private enum CodingKeys: String, CodingKey {
    case type
    case first
    case second
    case trigger
    case direction
  }

  private enum InputType: String, Codable {
    case rocker
    case wheel
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(InputType.self, forKey: .type) {
    case .rocker:
      self = .rocker(
        first: try container.decode(
          GestureTriggerButton.self,
          forKey: .first
        ),
        second: try container.decode(
          GestureTriggerButton.self,
          forKey: .second
        )
      )
    case .wheel:
      self = .wheel(
        trigger: try container.decode(
          GestureTriggerButton.self,
          forKey: .trigger
        ),
        direction: try container.decode(
          CompoundScrollDirection.self,
          forKey: .direction
        )
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .rocker(let first, let second):
      try container.encode(InputType.rocker, forKey: .type)
      try container.encode(first, forKey: .first)
      try container.encode(second, forKey: .second)
    case .wheel(let trigger, let direction):
      try container.encode(InputType.wheel, forKey: .type)
      try container.encode(trigger, forKey: .trigger)
      try container.encode(direction, forKey: .direction)
    }
  }
}

public struct CompoundGestureBinding:
  Codable,
  Equatable,
  Identifiable,
  Sendable
{
  public let id: UUID
  public var name: String
  public var isEnabled: Bool
  public var input: CompoundGestureInput
  public var action: GestureAction
  public var appScope: AppScope
  public var priority: Int

  public init(
    id: UUID = UUID(),
    name: String,
    isEnabled: Bool = false,
    input: CompoundGestureInput,
    action: GestureAction,
    appScope: AppScope = .all,
    priority: Int = 0
  ) {
    self.id = id
    self.name = name
    self.isEnabled = isEnabled
    self.input = input
    self.action = action
    self.appScope = appScope
    self.priority = priority
  }
}
