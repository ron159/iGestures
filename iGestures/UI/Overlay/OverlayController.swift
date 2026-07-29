import AppKit
import QuartzCore
import os

@MainActor
final class OverlayController {
  let eventSink: OverlayEventBuffer

  private static let performanceLog = OSLog(
    subsystem: "com.ron159.igestures",
    category: "Performance"
  )
  private var displayLink: CADisplayLink!
  private var screenLayout = ScreenLayout.current
  private var screenOverlays: [ScreenOverlay]

  init(eventSink: OverlayEventBuffer = OverlayEventBuffer()) {
    self.eventSink = eventSink
    self.screenOverlays = screenLayout.screens.map(ScreenOverlay.init)
    configureDisplayLink(isPaused: true)

    eventSink.setWakeHandler { [weak self] in
      Task { @MainActor [weak self] in
        self?.wakeDisplayLink()
      }
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
      updateScreenOverlays(for: .current)
      for overlay in screenOverlays {
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
      for overlay in screenOverlays {
        overlay.pathView.clear()
        overlay.panel.orderOut(nil)
      }
      displayLink.isPaused = true
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
    screenOverlays = layout.screens.map(ScreenOverlay.init)
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

  init(screen: ScreenLayout.Screen) {
    self.screen = screen
    self.pathView = GesturePathView(
      frame: NSRect(origin: .zero, size: screen.appKitFrame.size)
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
  private let shapeLayer = CAShapeLayer()
  private var path = CGMutablePath()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    shapeLayer.fillColor = NSColor.clear.cgColor
    shapeLayer.lineCap = .round
    shapeLayer.lineJoin = .round
    shapeLayer.lineWidth = 4
    shapeLayer.strokeColor =
      NSColor.controlAccentColor
      .withAlphaComponent(
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
          ? 1
          : 0.9
      ).cgColor
    layer?.addSublayer(shapeLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func layout() {
    super.layout()
    shapeLayer.frame = bounds
  }

  func begin(at point: CGPoint, scale: CGFloat) {
    path = CGMutablePath()
    path.move(to: point)
    shapeLayer.contentsScale = scale
    commitPath()
  }

  func append(_ points: [CGPoint]) {
    for point in points {
      path.addLine(to: point)
    }
    commitPath()
  }

  func clear() {
    path = CGMutablePath()
    commitPath()
  }

  private func commitPath() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shapeLayer.path = path.copy()
    CATransaction.commit()
  }
}
