import AppKit
import QuartzCore
import os

@MainActor
final class OverlayController {
  let eventSink: OverlayEventBuffer
  let feedbackSink: GestureFeedbackBuffer

  private static let performanceLog = OSLog(
    subsystem: "com.ron159.igestures",
    category: "Performance"
  )
  private var displayLink: CADisplayLink!
  private var screenLayout = ScreenLayout.current
  private var screenOverlays: [ScreenOverlay]
  private var trailColor = NSColor.controlAccentColor
  private let feedbackPanel: NSPanel
  private let feedbackLabel: NSTextField
  private var feedbackTask: Task<Void, Never>?
  private var feedbackPresentationGeneration = 0
  private var feedbackGlassViewStorage: NSView?
  private let feedbackIconView = NSImageView()
  private var isHapticFeedbackEnabled = false
  var onInspectDiagnostic: (() -> Void)?
  private let inspectButton = NSButton(
    title: String(localized: "Inspect…"), target: nil, action: nil)
  private let previewPanel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 38),
    styleMask: .borderless, backing: .buffered, defer: false
  )
  private var previewGlassViewStorage: NSView?
  private let previewIconView = NSImageView()
  private let previewLabel = NSTextField(labelWithString: "")
  private var previewPoints: [GesturePoint] = []
  private var previewContext: GesturePreviewContext?
  private var previewTask: Task<Void, Never>?
  private var previewGeneration = 0
  private var previewPresentationGeneration = 0
  private var isPreviewEnabled = true
  private var isPreviewEligible = false
  private var currentPreviewMatched = false
  private var trailDismissGeneration = 0
  private var trailDismissTask: Task<Void, Never>?

  init(
    eventSink: OverlayEventBuffer = OverlayEventBuffer(),
    feedbackSink: GestureFeedbackBuffer = GestureFeedbackBuffer()
  ) {
    self.eventSink = eventSink
    self.feedbackSink = feedbackSink
    self.screenOverlays = screenLayout.screens.map {
      ScreenOverlay(screen: $0)
    }
    self.feedbackLabel = NSTextField(labelWithString: "")
    self.feedbackPanel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 58),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    configureDisplayLink(isPaused: true)
    configureFeedbackPanel()
    configurePreviewPanel()

    eventSink.setWakeHandler { [weak self] in
      Task { @MainActor [weak self] in
        self?.wakeDisplayLink()
      }
    }
    feedbackSink.setHandler { [weak self] feedback in
      Task { @MainActor [weak self] in
        self?.showFeedback(feedback)
      }
    }
  }

  private func configurePreviewPanel() {
    previewPanel.isOpaque = false
    previewPanel.hasShadow = true
    previewPanel.ignoresMouseEvents = true
    previewPanel.hidesOnDeactivate = false
    previewPanel.isReleasedWhenClosed = false
    previewPanel.level = .statusBar
    previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    previewLabel.font = .systemFont(ofSize: 13, weight: .medium)
    previewLabel.lineBreakMode = .byTruncatingMiddle

    if #available(macOS 26.0, *) {
      previewPanel.backgroundColor = .clear
      let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 38))
      previewIconView.image = NSImage(
        systemSymbolName: "hand.draw.fill",
        accessibilityDescription: nil
      )
      previewIconView.symbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: 13,
        weight: .semibold
      )
      previewIconView.contentTintColor = .controlAccentColor
      previewIconView.frame = NSRect(x: 14, y: 10, width: 18, height: 18)
      previewLabel.frame = NSRect(x: 38, y: 9, width: 268, height: 20)
      container.addSubview(previewIconView)
      container.addSubview(previewLabel)

      let glassView = NSGlassEffectView(frame: container.bounds)
      glassView.style = .regular
      glassView.cornerRadius = 19
      glassView.contentView = container
      previewPanel.contentView = glassView
      previewGlassViewStorage = glassView
    } else {
      previewPanel.backgroundColor = .windowBackgroundColor.withAlphaComponent(0.94)
      previewLabel.frame = NSRect(x: 12, y: 10, width: 296, height: 20)
      previewPanel.contentView?.addSubview(previewLabel)
    }
  }

  private func configureFeedbackPanel() {
    feedbackPanel.isOpaque = false
    feedbackPanel.hasShadow = true
    feedbackPanel.ignoresMouseEvents = true
    feedbackPanel.hidesOnDeactivate = false
    feedbackPanel.isReleasedWhenClosed = false
    feedbackPanel.level = .statusBar
    feedbackPanel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
    ]
    feedbackLabel.font = .systemFont(ofSize: 14, weight: .medium)
    inspectButton.target = self
    inspectButton.action = #selector(inspectDiagnostic)
    inspectButton.bezelStyle = .rounded
    inspectButton.isHidden = true

    if #available(macOS 26.0, *) {
      feedbackPanel.backgroundColor = .clear
      let contentRect = feedbackPanel.contentRect(forFrameRect: feedbackPanel.frame)
      let container = NSView(frame: contentRect)
      feedbackIconView.symbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: 16,
        weight: .semibold
      )
      feedbackIconView.frame = NSRect(x: 16, y: 19, width: 20, height: 20)
      feedbackLabel.alignment = .left
      feedbackLabel.frame = NSRect(x: 44, y: 12, width: 260, height: 34)
      container.addSubview(feedbackIconView)
      container.addSubview(feedbackLabel)
      container.addSubview(inspectButton)

      let glassView = NSGlassEffectView(frame: contentRect)
      glassView.style = .regular
      glassView.cornerRadius = 22
      glassView.contentView = container
      feedbackPanel.contentView = glassView
      feedbackGlassViewStorage = glassView
    } else {
      feedbackPanel.backgroundColor = .windowBackgroundColor.withAlphaComponent(
        0.94
      )
      feedbackLabel.alignment = .center
      feedbackLabel.frame = NSRect(x: 12, y: 12, width: 296, height: 34)
      feedbackPanel.contentView = NSView(
        frame: feedbackPanel.contentRect(forFrameRect: feedbackPanel.frame)
      )
      feedbackPanel.contentView?.addSubview(feedbackLabel)
      feedbackPanel.contentView?.addSubview(inspectButton)
    }
  }

  private func showFeedback(_ feedback: GestureFeedback) {
    feedbackTask?.cancel()
    feedbackPresentationGeneration += 1
    let generation = feedbackPresentationGeneration
    let hasDetail: Bool
    if case .diagnostic = feedback { hasDetail = true } else { hasDetail = false }

    let width: CGFloat = hasDetail ? 452 : 332
    let height: CGFloat = hasDetail ? 74 : 58
    feedbackPanel.setContentSize(NSSize(width: width, height: height))
    feedbackPanel.ignoresMouseEvents = !hasDetail
    feedbackLabel.maximumNumberOfLines = 3
    feedbackLabel.lineBreakMode = .byWordWrapping
    feedbackLabel.stringValue = feedbackText(feedback)

    if #available(macOS 26.0, *),
      let glassView = feedbackGlassViewStorage as? NSGlassEffectView
    {
      glassView.frame = NSRect(x: 0, y: 0, width: width, height: height)
      glassView.cornerRadius = hasDetail ? 22 : 29
      glassView.contentView?.frame = glassView.bounds
      glassView.tintColor =
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        ? nil
        : feedbackTintColor(feedback)
      if #available(macOS 27.0, *) {
        glassView.effectIsInteractive = hasDetail
      }

      let style = feedbackSymbolStyle(feedback)
      feedbackIconView.image = NSImage(
        systemSymbolName: style.symbolName,
        accessibilityDescription: nil
      )
      feedbackIconView.contentTintColor = style.color
      feedbackIconView.frame = NSRect(x: 18, y: (height - 20) / 2, width: 20, height: 20)

      let labelWidth = hasDetail ? (width - 154) : (width - 64)
      let labelHeight: CGFloat = hasDetail ? 46 : 24
      feedbackLabel.alignment = .left
      feedbackLabel.frame = NSRect(
        x: 46,
        y: (height - labelHeight) / 2,
        width: labelWidth,
        height: labelHeight
      )
      inspectButton.frame = NSRect(x: width - 102, y: (height - 30) / 2, width: 88, height: 30)
      inspectButton.isHidden = !hasDetail
    } else {
      feedbackPanel.setContentSize(NSSize(width: hasDetail ? 440 : 320, height: 70))
      feedbackLabel.frame = NSRect(x: 12, y: 12, width: hasDetail ? 318 : 296, height: 46)
      inspectButton.frame = NSRect(x: 340, y: 20, width: 88, height: 30)
      inspectButton.isHidden = !hasDetail
    }

    let mouseLocation = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first {
        $0.frame.contains(mouseLocation)
      } ?? NSScreen.main
    if let screen {
      let frame = feedbackPanel.frame
      feedbackPanel.setFrameOrigin(
        CGPoint(
          x: screen.visibleFrame.midX - (frame.width / 2),
          y: screen.visibleFrame.minY + 48
        )
      )
    }

    if #available(macOS 26.0, *),
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    {
      feedbackPanel.alphaValue = 0
      feedbackPanel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.16
        feedbackPanel.animator().alphaValue = 1
      }
    } else {
      feedbackPanel.alphaValue = 1
      feedbackPanel.orderFrontRegardless()
    }

    if isHapticFeedbackEnabled {
      NSHapticFeedbackManager.defaultPerformer.perform(
        hapticPattern(feedback),
        performanceTime: .now
      )
    }
    feedbackTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(hasDetail ? 6 : 1.4))
      guard !Task.isCancelled, let self, generation == self.feedbackPresentationGeneration else {
        return
      }
      self.dismissFeedbackPanel(generation: generation)
    }
  }

  private func dismissFeedbackPanel(generation: Int? = nil) {
    if #available(macOS 26.0, *),
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      feedbackPanel.isVisible
    {
      let activeGeneration = generation ?? feedbackPresentationGeneration
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = 0.18
          feedbackPanel.animator().alphaValue = 0
        },
        completionHandler: { [weak self] in
          Task { @MainActor [weak self] in
            guard let self, activeGeneration == self.feedbackPresentationGeneration else { return }
            self.feedbackPanel.orderOut(nil)
            self.feedbackPanel.alphaValue = 1
          }
        }
      )
    } else {
      feedbackPanel.orderOut(nil)
      feedbackPanel.alphaValue = 1
    }
  }

  @objc private func inspectDiagnostic() {
    feedbackTask?.cancel()
    feedbackPresentationGeneration += 1
    feedbackPanel.orderOut(nil)
    feedbackPanel.alphaValue = 1
    onInspectDiagnostic?()
  }

  func setHapticFeedbackEnabled(_ enabled: Bool) {
    isHapticFeedbackEnabled = enabled
  }

  func setFeedbackEnabled(_ enabled: Bool) {
    feedbackSink.setEnabled(enabled)
    isPreviewEnabled = enabled
    if !enabled {
      clearPreview()
      feedbackTask?.cancel()
      feedbackPresentationGeneration += 1
      feedbackPanel.orderOut(nil)
      feedbackPanel.alphaValue = 1
    }
  }

  private func clearPreview() {
    previewGeneration += 1
    previewPresentationGeneration += 1
    previewTask?.cancel()
    previewTask = nil
    previewPanel.orderOut(nil)
    previewPanel.alphaValue = 1
    previewPoints.removeAll(keepingCapacity: true)
    previewContext = nil
    isPreviewEligible = false
    currentPreviewMatched = false
  }

  private func schedulePreview() {
    guard isPreviewEnabled, isPreviewEligible, previewTask == nil, previewContext != nil else {
      return
    }
    let generation = previewGeneration
    previewTask = Task { @MainActor [weak self] in
      // Coalesce mouse events and keep recognition off the Event Tap and drawing threads.
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled, let self, generation == previewGeneration,
        let context = previewContext
      else { return }
      let points = previewPoints
      let match = await Task.detached(priority: .utility) { context.match(points) }.value
      guard !Task.isCancelled, generation == previewGeneration else { return }
      previewTask = nil
      if let match, previewContext?.matchContext == context.matchContext,
        previewContext?.useSecondaryAction == context.useSecondaryAction
      {
        currentPreviewMatched = true
        previewLabel.stringValue = String(format: String(localized: "On release: %@"), match.name)
        let panelWidth: CGFloat
        if #available(macOS 26.0, *),
          let glassView = previewGlassViewStorage as? NSGlassEffectView
        {
          let textWidth = ceil(previewLabel.intrinsicContentSize.width)
          panelWidth = min(340, max(148, textWidth + 56))
          previewPanel.setContentSize(NSSize(width: panelWidth, height: 38))
          glassView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 38)
          glassView.cornerRadius = 19
          glassView.contentView?.frame = glassView.bounds
          previewLabel.frame = NSRect(x: 38, y: 9, width: panelWidth - 52, height: 20)
        } else {
          panelWidth = 320
        }

        let location = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) {
          let bounds = screen.visibleFrame
          let wasVisible = previewPanel.isVisible
          previewPanel.setFrameOrigin(
            NSPoint(
              x: max(bounds.minX, min(location.x + 20, bounds.maxX - panelWidth)),
              y: max(bounds.minY, min(location.y - 55, bounds.maxY - 38))
            ))
          if #available(macOS 26.0, *),
            !wasVisible,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
          {
            previewPanel.alphaValue = 0
            previewPanel.orderFrontRegardless()
            let presentationGen = previewPresentationGeneration
            NSAnimationContext.runAnimationGroup(
              { context in
                context.duration = 0.14
                if presentationGen == previewPresentationGeneration {
                  previewPanel.animator().alphaValue = 1
                }
              },
              completionHandler: nil
            )
          } else {
            previewPanel.alphaValue = 1
            previewPanel.orderFrontRegardless()
          }
        }
      } else {
        currentPreviewMatched = false
        previewPanel.orderOut(nil)
        previewPanel.alphaValue = 1
      }
      if previewPoints != points || previewContext?.matchContext != context.matchContext
        || previewContext?.useSecondaryAction != context.useSecondaryAction
      {
        schedulePreview()
      }
    }
  }

  private func feedbackSymbolStyle(
    _ feedback: GestureFeedback
  ) -> (symbolName: String, color: NSColor) {
    switch feedback {
    case .executed:
      ("checkmark.circle.fill", .systemGreen)
    case .noMatch, .ambiguous:
      ("questionmark.circle.fill", .systemOrange)
    case .actionFailed:
      ("exclamationmark.triangle.fill", .systemRed)
    case .diagnostic:
      ("exclamationmark.triangle.fill", .systemOrange)
    case .cancelled:
      ("xmark.circle.fill", .secondaryLabelColor)
    }
  }

  private func feedbackTintColor(_ feedback: GestureFeedback) -> NSColor? {
    switch feedback {
    case .executed:
      NSColor.systemGreen.withAlphaComponent(0.08)
    case .noMatch, .ambiguous, .diagnostic:
      NSColor.systemOrange.withAlphaComponent(0.10)
    case .actionFailed:
      NSColor.systemRed.withAlphaComponent(0.10)
    case .cancelled:
      nil
    }
  }

  func setTrailColor(_ color: NSColor) {
    trailColor = color
    for overlay in screenOverlays {
      overlay.pathView.setStrokeColor(color)
    }
  }

  private func hapticPattern(
    _ feedback: GestureFeedback
  ) -> NSHapticFeedbackManager.FeedbackPattern {
    switch feedback {
    case .executed:
      .alignment
    case .noMatch, .ambiguous, .actionFailed, .cancelled, .diagnostic:
      .generic
    }
  }

  private func feedbackText(_ feedback: GestureFeedback) -> String {
    switch feedback {
    case .executed(let mappingName):
      String(
        format: String(localized: "Executed: %@"),
        mappingName
      )
    case .noMatch:
      String(localized: "Gesture not recognized. Try a clearer stroke.")
    case .ambiguous:
      String(
        localized:
          "Gesture is ambiguous. Adjust or retrain similar gestures."
      )
    case .actionFailed(let mappingName):
      String(
        format: String(
          localized: "“%@” matched, but its action failed."
        ),
        mappingName
      )
    case .cancelled:
      String(localized: "Gesture cancelled.")
    case .diagnostic(let detail):
      detail.summary
    }
  }

  private func wakeDisplayLink() {
    displayLink.isPaused = false
    processPendingUpdate()
  }

  @objc
  private func displayLinkDidFire(_ displayLink: CADisplayLink) {
    processPendingUpdate()
  }

  private func processPendingUpdate() {
    guard let update = eventSink.drain() else { return }
    let signpostID = OSSignpostID(log: Self.performanceLog)
    os_signpost(
      .begin,
      log: Self.performanceLog,
      name: "OverlayUpdate",
      signpostID: signpostID
    )
    defer {
      os_signpost(
        .end,
        log: Self.performanceLog,
        name: "OverlayUpdate",
        signpostID: signpostID
      )
    }

    if let startPoint = update.startPoint {
      trailDismissGeneration += 1
      trailDismissTask?.cancel()
      trailDismissTask = nil
      clearPreview()
      previewPoints = [startPoint]
      isPreviewEligible = true
      updateScreenOverlays(for: .current)
      for overlay in screenOverlays {
        overlay.pathView.resetPresentation()
        overlay.pathView.begin(
          at: screenLayout.localPoint(
            for: startPoint,
            relativeTo: overlay.screen.appKitFrame
          ),
          scale: overlay.screen.scale
        )
        overlay.panel.orderFrontRegardless()
      }
    }
    if !update.points.isEmpty {
      if isPreviewEligible && previewPoints.count + update.points.count <= 4_096 {
        previewPoints.append(contentsOf: update.points)
      } else {
        clearPreview()
      }
      for overlay in screenOverlays {
        overlay.pathView.append(
          update.points.map {
            screenLayout.localPoint(
              for: $0,
              relativeTo: overlay.screen.appKitFrame
            )
          }
        )
      }
    }
    if update.shouldHide {
      let matchedOnRelease =
        currentPreviewMatched
        || (isPreviewEligible
          && previewPoints.count >= 2
          && (previewContext?.match(previewPoints) != nil))
      clearPreview()
      let shouldAnimateDismiss: Bool
      if #available(macOS 26.0, *) {
        shouldAnimateDismiss =
          !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
          && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
          && screenOverlays.contains { $0.pathView.hasVisibleStroke }
      } else {
        shouldAnimateDismiss = false
      }

      if shouldAnimateDismiss {
        trailDismissGeneration += 1
        let generation = trailDismissGeneration
        trailDismissTask?.cancel()
        for overlay in screenOverlays {
          overlay.pathView.playReleaseAnimation(matched: matchedOnRelease)
        }
        trailDismissTask = Task { @MainActor [weak self] in
          try? await Task.sleep(for: .milliseconds(matchedOnRelease ? 250 : 140))
          guard !Task.isCancelled, let self, generation == trailDismissGeneration else { return }
          trailDismissTask = nil
          for overlay in screenOverlays {
            overlay.pathView.clear()
            overlay.pathView.resetPresentation()
            overlay.panel.orderOut(nil)
          }
        }
      } else {
        trailDismissGeneration += 1
        trailDismissTask?.cancel()
        trailDismissTask = nil
        for overlay in screenOverlays {
          overlay.pathView.clear()
          overlay.pathView.resetPresentation()
          overlay.panel.orderOut(nil)
        }
      }
      displayLink.isPaused = true
    } else {
      previewContext = update.previewContext
      schedulePreview()
    }
  }

  private func updateScreenOverlays(for layout: ScreenLayout) {
    guard layout != screenLayout else { return }
    let wasPaused = displayLink.isPaused
    displayLink.invalidate()
    for overlay in screenOverlays {
      overlay.panel.orderOut(nil)
    }
    screenLayout = layout
    screenOverlays = layout.screens.map {
      ScreenOverlay(screen: $0, trailColor: trailColor)
    }
    configureDisplayLink(isPaused: wasPaused)
  }

  private func configureDisplayLink(isPaused: Bool) {
    guard let panel = screenOverlays.first?.panel else {
      preconditionFailure("A screen overlay is required")
    }
    displayLink = panel.displayLink(
      target: self,
      selector: #selector(displayLinkDidFire)
    )
    displayLink.add(to: .main, forMode: .common)
    displayLink.isPaused = isPaused
  }
}

@MainActor
private final class ScreenOverlay {
  let screen: ScreenLayout.Screen
  let panel: NSPanel
  let pathView: GesturePathView

  init(
    screen: ScreenLayout.Screen,
    trailColor: NSColor = .controlAccentColor
  ) {
    self.screen = screen
    self.pathView = GesturePathView(
      frame: NSRect(origin: .zero, size: screen.appKitFrame.size),
      trailColor: trailColor
    )
    self.panel = NSPanel(
      contentRect: screen.appKitFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )

    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
    ]
    pathView.autoresizingMask = [.width, .height]
    panel.contentView = pathView
  }
}

struct ScreenLayout: Equatable {
  struct Screen {
    let displayID: CGDirectDisplayID
    let appKitFrame: CGRect
    let quartzFrame: CGRect
    let scale: CGFloat
  }

  let screens: [Screen]

  static var current: ScreenLayout {
    let screens = NSScreen.screens.compactMap { screen -> Screen? in
      guard
        let number = screen.deviceDescription[
          NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
      else {
        return nil
      }
      return Screen(
        displayID: CGDirectDisplayID(number.uint32Value),
        appKitFrame: screen.frame,
        quartzFrame: CGDisplayBounds(
          CGDirectDisplayID(number.uint32Value)
        ),
        scale: screen.backingScaleFactor
      )
    }
    if !screens.isEmpty {
      return ScreenLayout(screens: screens)
    }

    let fallbackFrame =
      NSScreen.main?.frame
      ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    return ScreenLayout(screens: [
      Screen(
        displayID: 0,
        appKitFrame: fallbackFrame,
        quartzFrame: CGRect(
          x: fallbackFrame.minX,
          y: 0,
          width: fallbackFrame.width,
          height: fallbackFrame.height
        ),
        scale: NSScreen.main?.backingScaleFactor ?? 2
      )
    ])
  }

  static func == (lhs: ScreenLayout, rhs: ScreenLayout) -> Bool {
    guard lhs.screens.count == rhs.screens.count else {
      return false
    }
    return zip(lhs.screens, rhs.screens).allSatisfy {
      $0.displayID == $1.displayID
        && $0.appKitFrame == $1.appKitFrame
        && $0.quartzFrame == $1.quartzFrame
        && $0.scale == $1.scale
    }
  }

  func localPoint(
    for point: GesturePoint,
    relativeTo frame: CGRect
  ) -> CGPoint {
    let quartzPoint = CGPoint(
      x: CGFloat(point.x),
      y: CGFloat(point.y)
    )
    let screen =
      screens.first(where: {
        $0.quartzFrame.contains(quartzPoint)
      }) ?? screens.min {
        distance(from: quartzPoint, to: $0.quartzFrame)
          < distance(from: quartzPoint, to: $1.quartzFrame)
      }!
    let appKitPoint = CGPoint(
      x: screen.appKitFrame.minX
        + quartzPoint.x
        - screen.quartzFrame.minX,
      y: screen.appKitFrame.maxY
        - quartzPoint.y
        + screen.quartzFrame.minY
    )
    return CGPoint(
      x: appKitPoint.x - frame.minX,
      y: appKitPoint.y - frame.minY
    )
  }

  private func distance(
    from point: CGPoint,
    to rect: CGRect
  ) -> CGFloat {
    let xDistance = max(
      0,
      max(rect.minX - point.x, point.x - rect.maxX)
    )
    let yDistance = max(
      0,
      max(rect.minY - point.y, point.y - rect.maxY)
    )
    return hypot(xDistance, yDistance)
  }
}

private final class GesturePathView: NSView {
  private let glowLayer = CAShapeLayer()
  private let shapeLayer = CAShapeLayer()
  private let coreLayer = CAShapeLayer()
  private let headOrbLayer = CAShapeLayer()
  private var points: [CGPoint] = []
  private var fallbackPath = CGMutablePath()
  private var trailColor: NSColor

  var hasVisibleStroke: Bool {
    !points.isEmpty
  }

  private var usesLuminousTrail: Bool {
    if #available(macOS 26.0, *) {
      return !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    return false
  }

  init(frame frameRect: NSRect, trailColor: NSColor) {
    self.trailColor = trailColor
    super.init(frame: frameRect)
    wantsLayer = true

    glowLayer.fillRule = .nonZero
    glowLayer.strokeColor = NSColor.clear.cgColor
    glowLayer.shadowOffset = .zero
    glowLayer.shadowRadius = 8.5
    glowLayer.shadowOpacity = 1
    glowLayer.isHidden = !usesLuminousTrail

    shapeLayer.fillRule = .nonZero
    shapeLayer.lineCap = .round
    shapeLayer.lineJoin = .round
    shapeLayer.lineWidth = 4

    coreLayer.fillRule = .nonZero
    coreLayer.strokeColor = NSColor.clear.cgColor
    coreLayer.isHidden = !usesLuminousTrail

    let headRect = CGRect(x: -2.4, y: -2.4, width: 4.8, height: 4.8)
    let headPath = CGPath(ellipseIn: headRect, transform: nil)
    headOrbLayer.bounds = headRect
    headOrbLayer.path = headPath
    headOrbLayer.shadowPath = headPath
    headOrbLayer.shadowOffset = .zero
    headOrbLayer.shadowRadius = 7.5
    headOrbLayer.shadowOpacity = 1
    headOrbLayer.isHidden = true

    setStrokeColor(trailColor)
    layer?.addSublayer(glowLayer)
    layer?.addSublayer(shapeLayer)
    layer?.addSublayer(coreLayer)
    layer?.addSublayer(headOrbLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func layout() {
    super.layout()
    glowLayer.frame = bounds
    shapeLayer.frame = bounds
    coreLayer.frame = bounds
  }

  func begin(at point: CGPoint, scale: CGFloat) {
    points = [point]
    fallbackPath = CGMutablePath()
    fallbackPath.move(to: point)

    let luminous = usesLuminousTrail
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    glowLayer.isHidden = !luminous
    glowLayer.contentsScale = scale
    shapeLayer.contentsScale = scale
    coreLayer.isHidden = !luminous
    coreLayer.contentsScale = scale
    headOrbLayer.contentsScale = scale
    if luminous {
      headOrbLayer.position = point
      headOrbLayer.isHidden = false
    } else {
      headOrbLayer.isHidden = true
    }
    CATransaction.commit()

    applyColors()
    commitPath()
  }

  func append(_ newPoints: [CGPoint]) {
    guard !newPoints.isEmpty else { return }
    for point in newPoints {
      points.append(point)
      fallbackPath.addLine(to: point)
    }
    commitPath()
  }

  func clear() {
    points.removeAll(keepingCapacity: true)
    fallbackPath = CGMutablePath()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    headOrbLayer.isHidden = true
    glowLayer.path = nil
    glowLayer.shadowPath = nil
    shapeLayer.path = nil
    coreLayer.path = nil
    CATransaction.commit()
  }

  func resetPresentation() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for sublayer in [glowLayer, shapeLayer, coreLayer, headOrbLayer] {
      sublayer.removeAllAnimations()
      sublayer.opacity = 1
    }
    glowLayer.shadowRadius = 8.5
    headOrbLayer.transform = CATransform3DIdentity
    CATransaction.commit()
  }

  func playReleaseAnimation(matched: Bool) {
    guard usesLuminousTrail else { return }

    let duration: CFTimeInterval = matched ? 0.24 : 0.13
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for sublayer in [glowLayer, shapeLayer, coreLayer, headOrbLayer] {
      sublayer.removeAllAnimations()
      sublayer.opacity = 0
    }
    CATransaction.commit()

    CATransaction.begin()
    if matched {
      let fadeKeyTimes: [NSNumber] = [0.0, 0.22, 1.0]

      let ribbonFade = CAKeyframeAnimation(keyPath: "opacity")
      ribbonFade.values = [1.0, 1.0, 0.0]
      ribbonFade.keyTimes = fadeKeyTimes
      ribbonFade.duration = duration
      ribbonFade.timingFunctions = [
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .easeIn),
      ]
      shapeLayer.add(ribbonFade, forKey: "luminousReleaseFade")
      coreLayer.add(ribbonFade, forKey: "luminousReleaseFade")
      glowLayer.add(ribbonFade, forKey: "luminousReleaseFade")

      let bloomRadius = CABasicAnimation(keyPath: "shadowRadius")
      bloomRadius.fromValue = 8.5
      bloomRadius.toValue = 17.0
      bloomRadius.duration = duration
      bloomRadius.timingFunction = CAMediaTimingFunction(name: .easeOut)
      glowLayer.add(bloomRadius, forKey: "luminousReleaseBloom")

      let headScale = CAKeyframeAnimation(keyPath: "transform.scale")
      headScale.values = [1.0, 1.55, 0.55]
      headScale.keyTimes = fadeKeyTimes
      headScale.duration = duration
      headScale.timingFunctions = [
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .easeIn),
      ]
      headOrbLayer.add(headScale, forKey: "luminousReleaseHeadScale")
      headOrbLayer.add(ribbonFade, forKey: "luminousReleaseFade")
    } else {
      let softFade = CABasicAnimation(keyPath: "opacity")
      softFade.fromValue = 1.0
      softFade.toValue = 0.0
      softFade.duration = duration
      softFade.timingFunction = CAMediaTimingFunction(name: .easeOut)
      for sublayer in [glowLayer, shapeLayer, coreLayer, headOrbLayer] {
        sublayer.add(softFade, forKey: "luminousSoftFade")
      }
    }
    CATransaction.commit()
  }

  func setStrokeColor(_ color: NSColor) {
    trailColor = color
    applyColors()
  }

  private func applyColors() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    if usesLuminousTrail {
      glowLayer.fillColor = trailColor.withAlphaComponent(0.28).cgColor
      glowLayer.shadowColor = trailColor.withAlphaComponent(0.95).cgColor
      glowLayer.shadowOpacity = 1
      shapeLayer.fillColor = trailColor.withAlphaComponent(0.95).cgColor
      shapeLayer.strokeColor = NSColor.clear.cgColor
      coreLayer.fillColor = NSColor.white.withAlphaComponent(0.92).cgColor
      headOrbLayer.fillColor = NSColor.white.withAlphaComponent(0.96).cgColor
      headOrbLayer.shadowColor = trailColor.withAlphaComponent(0.95).cgColor
    } else {
      shapeLayer.fillColor = NSColor.clear.cgColor
      shapeLayer.strokeColor = trailColor.withAlphaComponent(reduceTransparency ? 1 : 0.9).cgColor
      glowLayer.fillColor = NSColor.clear.cgColor
      glowLayer.shadowOpacity = 0
    }
    CATransaction.commit()
  }

  private func commitPath() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if usesLuminousTrail {
      let ribbon = LuminousTrailGeometry.buildRibbon(from: points, maxRadius: 2.8)
      shapeLayer.path = ribbon.bodyPath
      glowLayer.path = ribbon.glowPath
      glowLayer.shadowPath = ribbon.glowPath
      coreLayer.path = ribbon.corePath
      if let head = ribbon.headPoint {
        headOrbLayer.position = head
        headOrbLayer.isHidden = false
      } else {
        headOrbLayer.isHidden = true
      }
    } else {
      let pathCopy = fallbackPath.copy()
      shapeLayer.path = pathCopy
      glowLayer.path = nil
      glowLayer.shadowPath = nil
      coreLayer.path = nil
      headOrbLayer.isHidden = true
    }
    CATransaction.commit()
  }
}
