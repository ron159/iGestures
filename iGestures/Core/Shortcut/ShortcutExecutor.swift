import CoreGraphics

public struct KeyboardEventDescriptor: Equatable, Sendable {
  public let keyCode: UInt16
  public let modifiers: UInt64
  public let isKeyDown: Bool
  public let sourceUserData: Int64

  public init(
    keyCode: UInt16,
    modifiers: UInt64,
    isKeyDown: Bool,
    sourceUserData: Int64
  ) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.isKeyDown = isKeyDown
    self.sourceUserData = sourceUserData
  }
}

public protocol ShortcutExecuting: Sendable {
  @discardableResult
  func execute(_ shortcut: KeyboardShortcut) -> Bool
}

public struct SystemShortcutExecutor: ShortcutExecuting {
  public init() {}

  public static func eventSequence(
    for shortcut: KeyboardShortcut
  ) -> [KeyboardEventDescriptor] {
    guard shortcut.isValid else { return [] }
    return [true, false].map {
      KeyboardEventDescriptor(
        keyCode: shortcut.keyCode,
        modifiers: shortcut.modifiers,
        isKeyDown: $0,
        sourceUserData: EventSourceMarker.syntheticEventUserData
      )
    }
  }

  @discardableResult
  public func execute(_ shortcut: KeyboardShortcut) -> Bool {
    let descriptors = Self.eventSequence(for: shortcut)
    guard descriptors.count == 2,
      let source = CGEventSource(stateID: .hidSystemState),
      let events = createEvents(descriptors, source: source)
    else {
      return false
    }

    for (event, descriptor) in zip(events, descriptors) {
      event.setIntegerValueField(
        .eventSourceUserData,
        value: descriptor.sourceUserData
      )
      event.post(tap: .cgSessionEventTap)
    }
    return true
  }

  private func createEvents(
    _ descriptors: [KeyboardEventDescriptor],
    source: CGEventSource
  ) -> [CGEvent]? {
    var events: [CGEvent] = []
    events.reserveCapacity(descriptors.count)

    for descriptor in descriptors {
      guard
        let event = CGEvent(
          keyboardEventSource: source,
          virtualKey: CGKeyCode(descriptor.keyCode),
          keyDown: descriptor.isKeyDown
        )
      else {
        return nil
      }
      event.flags = CGEventFlags(rawValue: descriptor.modifiers)
      events.append(event)
    }
    return events
  }
}
