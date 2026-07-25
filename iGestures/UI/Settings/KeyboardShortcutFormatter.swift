import AppKit
import CoreGraphics

enum KeyboardShortcutFormatter {
  static func string(for shortcut: KeyboardShortcut) -> String {
    guard shortcut.isValid else {
      return String(localized: "No Shortcut")
    }

    let flags = CGEventFlags(rawValue: shortcut.modifiers)
    var parts: [String] = []
    if flags.contains(.maskControl) {
      parts.append("⌃")
    }
    if flags.contains(.maskAlternate) {
      parts.append("⌥")
    }
    if flags.contains(.maskShift) {
      parts.append("⇧")
    }
    if flags.contains(.maskCommand) {
      parts.append("⌘")
    }
    if flags.contains(.maskSecondaryFn) {
      parts.append("fn")
    }
    parts.append(keyString(for: shortcut.keyCode))
    return parts.joined()
  }

  private static func keyString(for keyCode: UInt16) -> String {
    if let specialKey = specialKeys[keyCode] {
      return specialKey
    }

    if let event = CGEvent(
      keyboardEventSource: nil,
      virtualKey: CGKeyCode(keyCode),
      keyDown: true
    ),
      let characters = NSEvent(cgEvent: event)?
        .charactersIgnoringModifiers,
      !characters.isEmpty
    {
      return characters.uppercased()
    }
    return String(
      format: String(localized: "Key %d"),
      Int(keyCode)
    )
  }

  private static let specialKeys: [UInt16: String] = [
    36: "↩",
    48: "⇥",
    49: String(localized: "Space"),
    51: "⌫",
    53: "⎋",
    64: "F17",
    79: "F18",
    80: "F19",
    90: "F20",
    96: "F5",
    97: "F6",
    98: "F7",
    99: "F3",
    100: "F8",
    101: "F9",
    103: "F11",
    105: "F13",
    106: "F16",
    107: "F14",
    109: "F10",
    111: "F12",
    113: "F15",
    115: "↖",
    116: "⇞",
    117: "⌦",
    118: "F4",
    119: "↘",
    120: "F2",
    121: "⇟",
    122: "F1",
    123: "←",
    124: "→",
    125: "↓",
    126: "↑",
  ]
}

extension SystemShortcutConflict {
  var localizedDescription: String {
    switch self {
    case .spotlight:
      String(
        localized:
          "This shortcut is commonly reserved by macOS for Spotlight."
      )
    case .appSwitcher:
      String(
        localized:
          "This shortcut is commonly reserved by macOS for app switching."
      )
    case .forceQuit:
      String(
        localized:
          "This shortcut is commonly reserved by macOS for Force Quit."
      )
    case .missionControl:
      String(
        localized:
          "This shortcut is commonly reserved by macOS for Mission Control."
      )
    case .characterViewer:
      String(
        localized:
          "This shortcut is commonly reserved by macOS for the character viewer."
      )
    }
  }
}
