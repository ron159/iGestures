import CoreGraphics

public enum ShortcutRecordingResult: Equatable, Sendable {
  case ignored
  case cancelled
  case cleared
  case recorded(KeyboardShortcut)
}

public enum ShortcutCaptureResult: Equatable, Sendable {
  case passThrough
  case suppress
  case captured(keyCode: UInt16, modifiers: UInt64)
}

public struct ShortcutCaptureState: Sendable {
  public private(set) var isRecording = false

  private var suppressedKeyCodes: Set<UInt16> = []

  public init() {}

  public mutating func begin() {
    isRecording = true
  }

  public mutating func cancel() {
    isRecording = false
  }

  public mutating func releaseSuppressedKeys() {
    suppressedKeyCodes.removeAll(keepingCapacity: true)
  }

  public mutating func reset() {
    isRecording = false
    releaseSuppressedKeys()
  }

  public mutating func handleKeyDown(
    keyCode: UInt16,
    modifiers: UInt64
  ) -> ShortcutCaptureResult {
    if suppressedKeyCodes.contains(keyCode) {
      return .suppress
    }
    guard isRecording else { return .passThrough }

    isRecording = false
    suppressedKeyCodes.insert(keyCode)
    return .captured(keyCode: keyCode, modifiers: modifiers)
  }

  public mutating func handleKeyUp(
    keyCode: UInt16
  ) -> ShortcutCaptureResult {
    guard suppressedKeyCodes.remove(keyCode) != nil else {
      return .passThrough
    }
    return .suppress
  }
}

public struct ShortcutRecordingSession: Sendable {
  public static let emptyShortcut = KeyboardShortcut(
    keyCode: UInt16.max,
    modifiers: 0
  )

  public private(set) var shortcut: KeyboardShortcut
  public private(set) var isRecording = false

  private let originalShortcut: KeyboardShortcut

  public init(shortcut: KeyboardShortcut) {
    self.shortcut = shortcut
    self.originalShortcut = shortcut
  }

  public mutating func begin() {
    isRecording = true
  }

  @discardableResult
  public mutating func handleKeyDown(
    keyCode: UInt16,
    modifiers: UInt64
  ) -> ShortcutRecordingResult {
    guard isRecording else { return .ignored }

    switch keyCode {
    case 53:
      shortcut = originalShortcut
      isRecording = false
      return .cancelled
    case 51, 117:
      shortcut = Self.emptyShortcut
      isRecording = false
      return .cleared
    default:
      let recordedShortcut = KeyboardShortcut(
        keyCode: keyCode,
        modifiers: Self.normalizedModifiers(modifiers)
      )
      shortcut = recordedShortcut
      isRecording = false
      return .recorded(recordedShortcut)
    }
  }

  public static func normalizedModifiers(_ modifiers: UInt64) -> UInt64 {
    let allowed =
      CGEventFlags.maskCommand.rawValue
      | CGEventFlags.maskAlternate.rawValue
      | CGEventFlags.maskControl.rawValue
      | CGEventFlags.maskShift.rawValue
      | CGEventFlags.maskSecondaryFn.rawValue
    return modifiers & allowed
  }
}
