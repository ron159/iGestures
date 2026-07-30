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

public enum SystemGestureAction: String, Codable, CaseIterable, Sendable {
  case missionControl
  case showDesktop
  case lockScreen
  case sleep
  case volumeUp
  case volumeDown
  case mute
  case brightnessUp
  case brightnessDown
  case appSwitcher
  case spotlight
  case launchpad
  case previousSpace
  case nextSpace
  case screenshotFullScreen
  case screenshotSelection
  case screenshotToolbar
  case playPause
  case previousTrack
  case nextTrack
  case emojiPicker
  case forceQuit
}

public enum WindowGestureAction: String, Codable, CaseIterable, Sendable {
  case leftHalf
  case rightHalf
  case topHalf
  case bottomHalf
  case topLeftQuarter
  case topRightQuarter
  case bottomLeftQuarter
  case bottomRightQuarter
  case leftThird
  case centerThird
  case rightThird
  case leftTwoThirds
  case rightTwoThirds
  case center
  case maximize
  case maximizeHeight
  case maximizeWidth
  case close
  case minimize
  case toggleFullScreen
  case previousDisplay
  case nextDisplay
  case restorePreviousFrame
}

public struct NormalizedWindowFrame: Codable, Hashable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(
    x: Double = 0.1,
    y: Double = 0.1,
    width: Double = 0.8,
    height: Double = 0.8
  ) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var isValid: Bool {
    [x, y, width, height].allSatisfy(\.isFinite)
      && (0...1).contains(x)
      && (0...1).contains(y)
      && width > 0
      && height > 0
      && x + width <= 1.000_001
      && y + height <= 1.000_001
  }
}

public struct ApplicationMenuAction: Codable, Hashable, Sendable {
  public var path: [String]

  public init(path: [String]) {
    self.path = path
  }

  public var normalizedPath: [String] {
    path.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
  }

  public var isValid: Bool {
    let normalizedPath = normalizedPath
    return !normalizedPath.isEmpty
      && normalizedPath.count <= 8
      && normalizedPath.allSatisfy { $0.utf8.count <= 120 }
  }
}

public enum AutomationScriptKind: String, Codable, CaseIterable, Sendable {
  case appleScript
  case shell
}

public struct AutomationScript: Codable, Hashable, Sendable {
  public var kind: AutomationScriptKind
  public var source: String
  public var timeout: TimeInterval
  public var isConfirmed: Bool

  public init(
    kind: AutomationScriptKind,
    source: String,
    timeout: TimeInterval = 10,
    isConfirmed: Bool = false
  ) {
    self.kind = kind
    self.source = source
    self.timeout = min(30, max(1, timeout))
    self.isConfirmed = isConfirmed
  }
}

public struct GestureActionStep: Codable, Hashable, Sendable {
  public var action: GestureAction
  public var delayAfter: TimeInterval

  public init(
    action: GestureAction,
    delayAfter: TimeInterval = 0
  ) {
    self.action = action
    self.delayAfter = min(5, max(0, delayAfter))
  }
}

public indirect enum GestureSequenceFailurePolicy:
  Codable,
  Hashable,
  Sendable
{
  case stop
  case `continue`
  case fallback(GestureAction)

  private enum CodingKeys: String, CodingKey {
    case type
    case action
  }

  private enum PolicyType: String, Codable {
    case stop
    case `continue`
    case fallback
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(PolicyType.self, forKey: .type) {
    case .stop:
      self = .stop
    case .continue:
      self = .continue
    case .fallback:
      self = .fallback(
        try container.decode(GestureAction.self, forKey: .action)
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .stop:
      try container.encode(PolicyType.stop, forKey: .type)
    case .continue:
      try container.encode(PolicyType.continue, forKey: .type)
    case .fallback(let action):
      try container.encode(PolicyType.fallback, forKey: .type)
      try container.encode(action, forKey: .action)
    }
  }
}

public struct GestureActionSequence: Codable, Hashable, Sendable {
  public var steps: [GestureActionStep]
  public var failurePolicy: GestureSequenceFailurePolicy

  public init(
    steps: [GestureActionStep],
    failurePolicy: GestureSequenceFailurePolicy = .stop
  ) {
    self.steps = steps
    self.failurePolicy = failurePolicy
  }
}

public indirect enum GestureAction: Codable, Hashable, Sendable {
  case keyboardShortcut(KeyboardShortcut)
  case openURL(String)
  case openPath(String)
  case launchApplication(bundleIdentifier: String)
  case system(SystemGestureAction)
  case window(WindowGestureAction)
  case customWindow(NormalizedWindowFrame)
  case typeText(String)
  case applicationMenu(ApplicationMenuAction)
  case appleShortcut(name: String)
  case sequence(GestureActionSequence)
  case script(AutomationScript)

  private enum CodingKeys: String, CodingKey {
    case type
    case shortcut
    case url
    case path
    case bundleIdentifier
    case systemAction
    case windowAction
    case windowFrame
    case text
    case menuAction
    case name
    case sequence
    case script
  }

  private enum ActionType: String, Codable {
    case keyboardShortcut
    case openURL
    case openPath
    case launchApplication
    case system
    case window
    case customWindow
    case typeText
    case applicationMenu
    case appleShortcut
    case sequence
    case script
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(ActionType.self, forKey: .type) {
    case .keyboardShortcut:
      self = .keyboardShortcut(
        try container.decode(
          KeyboardShortcut.self,
          forKey: .shortcut
        )
      )
    case .openURL:
      self = .openURL(
        try container.decode(String.self, forKey: .url)
      )
    case .openPath:
      self = .openPath(
        try container.decode(String.self, forKey: .path)
      )
    case .launchApplication:
      self = .launchApplication(
        bundleIdentifier: try container.decode(
          String.self,
          forKey: .bundleIdentifier
        )
      )
    case .system:
      self = .system(
        try container.decode(
          SystemGestureAction.self,
          forKey: .systemAction
        )
      )
    case .window:
      self = .window(
        try container.decode(
          WindowGestureAction.self,
          forKey: .windowAction
        )
      )
    case .customWindow:
      self = .customWindow(
        try container.decode(
          NormalizedWindowFrame.self,
          forKey: .windowFrame
        )
      )
    case .typeText:
      self = .typeText(
        try container.decode(String.self, forKey: .text)
      )
    case .applicationMenu:
      self = .applicationMenu(
        try container.decode(
          ApplicationMenuAction.self,
          forKey: .menuAction
        )
      )
    case .appleShortcut:
      self = .appleShortcut(
        name: try container.decode(String.self, forKey: .name)
      )
    case .sequence:
      self = .sequence(
        try container.decode(
          GestureActionSequence.self,
          forKey: .sequence
        )
      )
    case .script:
      self = .script(
        try container.decode(
          AutomationScript.self,
          forKey: .script
        )
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .keyboardShortcut(let shortcut):
      try container.encode(
        ActionType.keyboardShortcut,
        forKey: .type
      )
      try container.encode(shortcut, forKey: .shortcut)
    case .openURL(let url):
      try container.encode(ActionType.openURL, forKey: .type)
      try container.encode(url, forKey: .url)
    case .openPath(let path):
      try container.encode(ActionType.openPath, forKey: .type)
      try container.encode(path, forKey: .path)
    case .launchApplication(let bundleIdentifier):
      try container.encode(
        ActionType.launchApplication,
        forKey: .type
      )
      try container.encode(
        bundleIdentifier,
        forKey: .bundleIdentifier
      )
    case .system(let action):
      try container.encode(ActionType.system, forKey: .type)
      try container.encode(action, forKey: .systemAction)
    case .window(let action):
      try container.encode(ActionType.window, forKey: .type)
      try container.encode(action, forKey: .windowAction)
    case .customWindow(let frame):
      try container.encode(ActionType.customWindow, forKey: .type)
      try container.encode(frame, forKey: .windowFrame)
    case .typeText(let text):
      try container.encode(ActionType.typeText, forKey: .type)
      try container.encode(text, forKey: .text)
    case .applicationMenu(let menuAction):
      try container.encode(
        ActionType.applicationMenu,
        forKey: .type
      )
      try container.encode(menuAction, forKey: .menuAction)
    case .appleShortcut(let name):
      try container.encode(
        ActionType.appleShortcut,
        forKey: .type
      )
      try container.encode(name, forKey: .name)
    case .sequence(let sequence):
      try container.encode(ActionType.sequence, forKey: .type)
      try container.encode(sequence, forKey: .sequence)
    case .script(let script):
      try container.encode(ActionType.script, forKey: .type)
      try container.encode(script, forKey: .script)
    }
  }

  public var isValid: Bool {
    isValid(allowingUnconfirmedScripts: false)
  }

  public func isValid(
    allowingUnconfirmedScripts: Bool
  ) -> Bool {
    isValid(
      allowingUnconfirmedScripts: allowingUnconfirmedScripts,
      depth: 0
    )
  }

  private func isValid(
    allowingUnconfirmedScripts: Bool,
    depth: Int
  ) -> Bool {
    guard depth <= 20 else { return false }
    switch self {
    case .keyboardShortcut(let shortcut):
      return shortcut.isValid
    case .openURL(let value):
      guard let components = URLComponents(string: value),
        let scheme = components.scheme?.lowercased(),
        scheme == "http" || scheme == "https",
        components.host != nil
      else {
        return false
      }
      return true
    case .openPath(let value):
      let normalized = value.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      return normalized.utf8.count <= 4_096
        && (normalized.hasPrefix("/")
          || normalized == "~"
          || normalized.hasPrefix("~/"))
    case .launchApplication(let bundleIdentifier):
      return !bundleIdentifier.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
    case .system, .window:
      return true
    case .customWindow(let frame):
      return frame.isValid
    case .typeText(let text):
      return !text.isEmpty && text.utf8.count <= 16 * 1_024
    case .applicationMenu(let menuAction):
      return menuAction.isValid
    case .appleShortcut(let name):
      return !name.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
    case .sequence(let sequence):
      let fallbackIsValid: Bool
      switch sequence.failurePolicy {
      case .stop, .continue:
        fallbackIsValid = true
      case .fallback(let action):
        fallbackIsValid = action.isValid(
          allowingUnconfirmedScripts:
            allowingUnconfirmedScripts,
          depth: depth + 1
        )
      }
      return fallbackIsValid
        && !sequence.steps.isEmpty
        && sequence.steps.count <= 20
        && sequence.steps.allSatisfy {
          $0.action.isValid(
            allowingUnconfirmedScripts:
              allowingUnconfirmedScripts,
            depth: depth + 1
          )
            && $0.delayAfter.isFinite
            && (0...5).contains($0.delayAfter)
        }
    case .script(let script):
      return (script.isConfirmed || allowingUnconfirmedScripts)
        && !script.source.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
        && script.source.utf8.count <= 64 * 1_024
        && script.timeout.isFinite
        && (1...30).contains(script.timeout)
    }
  }

  public var keyboardShortcut: KeyboardShortcut? {
    guard case .keyboardShortcut(let shortcut) = self else {
      return nil
    }
    return shortcut
  }

  public var scripts: [AutomationScript] {
    switch self {
    case .sequence(let sequence):
      return sequence.steps.flatMap { $0.action.scripts }
        + sequenceFallbackScripts(sequence.failurePolicy)
    case .script(let script):
      return [script]
    case .keyboardShortcut, .openURL, .openPath, .launchApplication,
      .system, .window, .customWindow, .typeText, .applicationMenu,
      .appleShortcut:
      return []
    }
  }

  public func disablingScripts() -> GestureAction {
    switch self {
    case .script(var script):
      script.isConfirmed = false
      return .script(script)
    case .sequence(var sequence):
      sequence.steps = sequence.steps.map {
        GestureActionStep(
          action: $0.action.disablingScripts(),
          delayAfter: $0.delayAfter
        )
      }
      if case .fallback(let action) = sequence.failurePolicy {
        sequence.failurePolicy = .fallback(
          action.disablingScripts()
        )
      }
      return .sequence(sequence)
    case .keyboardShortcut, .openURL, .openPath, .launchApplication,
      .system, .window, .customWindow, .typeText, .applicationMenu,
      .appleShortcut:
      return self
    }
  }

  private func sequenceFallbackScripts(
    _ policy: GestureSequenceFailurePolicy
  ) -> [AutomationScript] {
    guard case .fallback(let action) = policy else { return [] }
    return action.scripts
  }
}

public struct ActionRequest: Equatable, Sendable {
  public let mappingID: UUID
  public let mappingName: String
  public let action: GestureAction
  public let repeatModeEnabled: Bool

  public init(
    mappingID: UUID,
    mappingName: String,
    action: GestureAction,
    repeatModeEnabled: Bool = false
  ) {
    self.mappingID = mappingID
    self.mappingName = mappingName
    self.action = action
    self.repeatModeEnabled = repeatModeEnabled
  }
}

public enum GestureInputDevice: Codable, Hashable, Sendable {
  case mouse(identifier: String?)
  case trackpad

  private enum CodingKeys: String, CodingKey {
    case type
    case identifier
  }

  private enum DeviceType: String, Codable {
    case mouse
    case trackpad
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(DeviceType.self, forKey: .type) {
    case .mouse:
      self = .mouse(
        identifier: try container.decodeIfPresent(
          String.self,
          forKey: .identifier
        )
      )
    case .trackpad:
      self = .trackpad
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .mouse(let identifier):
      try container.encode(DeviceType.mouse, forKey: .type)
      try container.encodeIfPresent(identifier, forKey: .identifier)
    case .trackpad:
      try container.encode(DeviceType.trackpad, forKey: .type)
    }
  }
}

public enum InputDeviceScope: Codable, Hashable, Sendable {
  case any
  case mouse(identifier: String?)
  case trackpad

  private enum CodingKeys: String, CodingKey {
    case type
    case identifier
  }

  private enum ScopeType: String, Codable {
    case any
    case mouse
    case trackpad
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(ScopeType.self, forKey: .type) {
    case .any:
      self = .any
    case .mouse:
      self = .mouse(
        identifier: try container.decodeIfPresent(
          String.self,
          forKey: .identifier
        )
      )
    case .trackpad:
      self = .trackpad
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .any:
      try container.encode(ScopeType.any, forKey: .type)
    case .mouse(let identifier):
      try container.encode(ScopeType.mouse, forKey: .type)
      try container.encodeIfPresent(identifier, forKey: .identifier)
    case .trackpad:
      try container.encode(ScopeType.trackpad, forKey: .type)
    }
  }

  public func includes(_ device: GestureInputDevice) -> Bool {
    switch (self, device) {
    case (.any, _), (.trackpad, .trackpad):
      return true
    case (.mouse(nil), .mouse):
      return true
    case (
      .mouse(let expected?),
      .mouse(let actual?)
    ):
      return expected == actual
    default:
      return false
    }
  }

  public var isDeviceSpecific: Bool {
    self != .any
  }

  public func competes(with other: InputDeviceScope) -> Bool {
    switch (self, other) {
    case (.any, .any), (.trackpad, .trackpad):
      return true
    case (.mouse(let left), .mouse(let right)):
      return left == nil || right == nil || left == right
    case (.any, _), (_, .any), (.mouse, .trackpad),
      (.trackpad, .mouse):
      return false
    }
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

  public func isApplicationSpecific(for bundleID: String?) -> Bool {
    guard let bundleID else { return false }
    guard case .only(let bundleIDs) = self else { return false }
    return bundleIDs.contains(bundleID)
  }

  public func overlaps(with other: AppScope) -> Bool {
    switch (self, other) {
    case (.all, _), (_, .all):
      return true
    case (.only(let left), .only(let right)):
      return !Set(left).isDisjoint(with: right)
    case (.only(let included), .allExcept(let excluded)),
      (.allExcept(let excluded), .only(let included)):
      return included.contains { !excluded.contains($0) }
    case (.allExcept, .allExcept):
      return true
    }
  }

  public func competes(with other: AppScope) -> Bool {
    switch (self, other) {
    case (.only, .only), (.all, .all), (.all, .allExcept),
      (.allExcept, .all), (.allExcept, .allExcept):
      overlaps(with: other)
    case (.only, .all), (.only, .allExcept),
      (.all, .only), (.allExcept, .only):
      false
    }
  }
}

public struct GestureMapping: Codable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var name: String
  public var isEnabled: Bool
  public var templates: [GestureTemplate]
  public var action: GestureAction
  public var secondaryAction: GestureAction?
  public var appScope: AppScope
  public var triggerButton: GestureTriggerButton?
  public var category: String?
  public var applicationGroupID: UUID?
  public var repeatModeEnabled: Bool
  public var deviceScope: InputDeviceScope
  public var priority: Int

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case isEnabled
    case templates
    case action
    case secondaryAction
    case shortcut
    case appScope
    case triggerButton
    case category
    case applicationGroupID
    case repeatModeEnabled
    case deviceScope
    case priority
  }

  public init(
    id: UUID = UUID(),
    name: String,
    isEnabled: Bool = true,
    templates: [GestureTemplate],
    action: GestureAction,
    secondaryAction: GestureAction? = nil,
    appScope: AppScope = .all,
    triggerButton: GestureTriggerButton? = nil,
    category: String? = nil,
    applicationGroupID: UUID? = nil,
    repeatModeEnabled: Bool = false,
    deviceScope: InputDeviceScope = .any,
    priority: Int = 0
  ) {
    self.id = id
    self.name = name
    self.isEnabled = isEnabled
    self.templates = templates
    self.action = action
    self.secondaryAction = secondaryAction
    self.appScope = appScope
    self.triggerButton = triggerButton
    self.category = category
    self.applicationGroupID = applicationGroupID
    self.repeatModeEnabled = repeatModeEnabled
    self.deviceScope = deviceScope
    self.priority = priority
  }

  public init(
    id: UUID = UUID(),
    name: String,
    isEnabled: Bool = true,
    templates: [GestureTemplate],
    shortcut: KeyboardShortcut,
    secondaryAction: GestureAction? = nil,
    appScope: AppScope = .all,
    triggerButton: GestureTriggerButton? = nil,
    category: String? = nil,
    applicationGroupID: UUID? = nil,
    repeatModeEnabled: Bool = false,
    deviceScope: InputDeviceScope = .any,
    priority: Int = 0
  ) {
    self.init(
      id: id,
      name: name,
      isEnabled: isEnabled,
      templates: templates,
      action: .keyboardShortcut(shortcut),
      secondaryAction: secondaryAction,
      appScope: appScope,
      triggerButton: triggerButton,
      category: category,
      applicationGroupID: applicationGroupID,
      repeatModeEnabled: repeatModeEnabled,
      deviceScope: deviceScope,
      priority: priority
    )
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    templates = try container.decode(
      [GestureTemplate].self,
      forKey: .templates
    )
    if let decodedAction = try container.decodeIfPresent(
      GestureAction.self,
      forKey: .action
    ) {
      action = decodedAction
    } else {
      action = .keyboardShortcut(
        try container.decode(
          KeyboardShortcut.self,
          forKey: .shortcut
        )
      )
    }
    secondaryAction = try container.decodeIfPresent(
      GestureAction.self,
      forKey: .secondaryAction
    )
    appScope = try container.decode(AppScope.self, forKey: .appScope)
    triggerButton = try container.decodeIfPresent(
      GestureTriggerButton.self,
      forKey: .triggerButton
    )
    category = try container.decodeIfPresent(
      String.self,
      forKey: .category
    )
    applicationGroupID = try container.decodeIfPresent(
      UUID.self,
      forKey: .applicationGroupID
    )
    repeatModeEnabled =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .repeatModeEnabled
      ) ?? false
    deviceScope =
      try container.decodeIfPresent(
        InputDeviceScope.self,
        forKey: .deviceScope
      ) ?? .any
    priority = try container.decode(Int.self, forKey: .priority)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(templates, forKey: .templates)
    try container.encode(action, forKey: .action)
    try container.encodeIfPresent(
      secondaryAction,
      forKey: .secondaryAction
    )
    try container.encode(appScope, forKey: .appScope)
    try container.encodeIfPresent(
      triggerButton,
      forKey: .triggerButton
    )
    try container.encodeIfPresent(category, forKey: .category)
    try container.encodeIfPresent(
      applicationGroupID,
      forKey: .applicationGroupID
    )
    try container.encode(
      repeatModeEnabled,
      forKey: .repeatModeEnabled
    )
    try container.encode(deviceScope, forKey: .deviceScope)
    try container.encode(priority, forKey: .priority)
  }

  public var shortcut: KeyboardShortcut {
    get {
      action.keyboardShortcut
        ?? ShortcutRecordingSession.emptyShortcut
    }
    set {
      action = .keyboardShortcut(newValue)
    }
  }
}
