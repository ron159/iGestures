import CoreGraphics

public enum SystemShortcutConflict: Equatable, Sendable {
  case spotlight
  case appSwitcher
  case forceQuit
  case missionControl
  case characterViewer
}

public struct SystemShortcutConflictDetector: Sendable {
  public init() {}

  public func conflict(
    for shortcut: KeyboardShortcut
  ) -> SystemShortcutConflict? {
    guard shortcut.isValid else { return nil }
    let modifiers = ShortcutRecordingSession.normalizedModifiers(
      shortcut.modifiers
    )
    let command = CGEventFlags.maskCommand.rawValue
    let option = CGEventFlags.maskAlternate.rawValue
    let control = CGEventFlags.maskControl.rawValue
    let shift = CGEventFlags.maskShift.rawValue

    switch (shortcut.keyCode, modifiers) {
    case (49, command):
      return .spotlight
    case (48, command), (48, command | shift):
      return .appSwitcher
    case (53, command | option):
      return .forceQuit
    case (123...126, control):
      return .missionControl
    case (49, command | control):
      return .characterViewer
    default:
      return nil
    }
  }
}
