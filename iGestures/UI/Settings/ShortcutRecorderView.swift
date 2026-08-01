import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
  @Binding var shortcut: KeyboardShortcut
  let model: AppModel

  func makeNSView(context: Context) -> ShortcutRecorderControl {
    let control = ShortcutRecorderControl()
    control.shortcut = shortcut
    control.onChange = { shortcut in
      self.shortcut = shortcut
    }
    configureCapture(for: control)
    return control
  }

  func updateNSView(
    _ control: ShortcutRecorderControl,
    context: Context
  ) {
    control.shortcut = shortcut
    control.onChange = { shortcut in
      self.shortcut = shortcut
    }
    configureCapture(for: control)
  }

  private func configureCapture(
    for control: ShortcutRecorderControl
  ) {
    control.beginSystemCapture = { handler in
      model.beginShortcutRecording(handler)
    }
    control.endSystemCapture = { id in
      model.endShortcutRecording(id: id)
    }
  }
}

@MainActor
final class ShortcutRecorderControl: NSControl {
  var shortcut = ShortcutRecordingSession.emptyShortcut {
    didSet {
      if session?.isRecording != true {
        updateLabel()
      }
    }
  }
  var onChange: ((KeyboardShortcut) -> Void)?
  var beginSystemCapture:
    (
      (@escaping EventTapManager.ShortcutRecordingHandler) -> UUID
    )?
  var endSystemCapture: ((UUID) -> Void)?

  private let label = NonInteractiveTextField(labelWithString: "")
  private var session: ShortcutRecordingSession?
  private var systemCaptureID: UUID?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.borderWidth = 1
    target = self
    action = #selector(beginRecording)

    label.alignment = .center
    label.lineBreakMode = .byTruncatingMiddle
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
      heightAnchor.constraint(equalToConstant: 28),
    ])
    updateAppearance()
    updateLabel()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    beginRecording()
  }

  @objc private func beginRecording() {
    guard window?.makeFirstResponder(self) == true else { return }
    stopSystemCapture()
    var recording = ShortcutRecordingSession(shortcut: shortcut)
    recording.begin()
    session = recording
    systemCaptureID = beginSystemCapture? { [weak self] keyCode, modifiers in
      Task { @MainActor [weak self] in
        self?.handleKeyDown(
          keyCode: keyCode,
          modifiers: modifiers
        )
      }
    }
    label.stringValue = String(localized: "Press Shortcut…")
    updateAppearance()
  }

  override func keyDown(with event: NSEvent) {
    guard session != nil else {
      super.keyDown(with: event)
      return
    }

    handleKeyDown(
      keyCode: event.keyCode,
      modifiers: UInt64(event.modifierFlags.rawValue)
    )
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard session != nil else {
      return super.performKeyEquivalent(with: event)
    }
    handleKeyDown(
      keyCode: event.keyCode,
      modifiers: UInt64(event.modifierFlags.rawValue)
    )
    return true
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil {
      cancelRecording()
    }
    super.viewWillMove(toWindow: newWindow)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateAppearance()
  }

  private func handleKeyDown(
    keyCode: UInt16,
    modifiers: UInt64
  ) {
    guard var recording = session else { return }
    let result = recording.handleKeyDown(
      keyCode: keyCode,
      modifiers: modifiers
    )
    session = recording

    switch result {
    case .recorded(let shortcut):
      commit(shortcut)
    case .cleared:
      commit(ShortcutRecordingSession.emptyShortcut)
    case .cancelled:
      cancelRecording()
    case .ignored:
      break
    }
  }

  override func resignFirstResponder() -> Bool {
    cancelRecording()
    return super.resignFirstResponder()
  }

  private func commit(_ shortcut: KeyboardShortcut) {
    self.shortcut = shortcut
    session = nil
    stopSystemCapture()
    onChange?(shortcut)
    updateAppearance()
  }

  private func cancelRecording() {
    session = nil
    stopSystemCapture()
    updateLabel()
    updateAppearance()
  }

  private func stopSystemCapture() {
    guard let systemCaptureID else { return }
    self.systemCaptureID = nil
    endSystemCapture?(systemCaptureID)
  }

  private func updateLabel() {
    label.stringValue = KeyboardShortcutFormatter.string(for: shortcut)
  }

  private func updateAppearance() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let isFocused = window?.firstResponder === self
      layer?.borderColor =
        (isFocused ? NSColor.controlAccentColor : NSColor.separatorColor)
        .cgColor
      layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
      label.textColor = NSColor.labelColor
    }
  }
}

private final class NonInteractiveTextField: NSTextField {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}
