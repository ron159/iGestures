import AppKit
import QuartzCore
import os

@MainActor
final class OverlayController {
  let eventSink: OverlayEventBuffer

  private let panel: NSPanel
  private static let performanceLog = OSLog(
    subsystem: "com.ron159.igestures",
    category: "Performance"
  )
  private let pathView: GesturePathView
  private var displayLink: CADisplayLink!
  private var screenLayout = ScreenLayout.current

  init(eventSink: OverlayEventBuffer = OverlayEventBuffer()) {
    self.eventSink = eventSink
    self.pathView = GesturePathView(frame: .zero)
    self.panel = NSPanel(
      contentRect: .zero,
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
    panel.contentView = pathView

    displayLink = panel.displayLink(
      target: self,
      selector: #selector(displayLinkDidFire)
    )
    displayLink.add(to: .main, forMode: .common)
    displayLink.isPaused = true

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
      screenLayout = .current
      panel.setFrame(screenLayout.appKitUnionFrame, display: false)
      pathView.frame = NSRect(
        origin: .zero,
        size: screenLayout.appKitUnionFrame.size
      )
      pathView.begin(
        at: screenLayout.localPoint(for: startPoint),
        scale: screenLayout.maximumScale
      )
      panel.orderFrontRegardless()
    }
    if !update.points.isEmpty {
      pathView.append(
        update.points.map(screenLayout.localPoint(for:))
      )
    }
    if update.shouldHide {
      pathView.clear()
      panel.orderOut(nil)
      displayLink.isPaused = true
    }
  }
}

private struct ScreenLayout {
  struct Screen {
    let appKitFrame: CGRect
    let quartzFrame: CGRect
    let scale: CGFloat
  }

  let screens: [Screen]
  let appKitUnionFrame: CGRect
  let maximumScale: CGFloat

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
        appKitFrame: screen.frame,
        quartzFrame: CGDisplayBounds(
          CGDirectDisplayID(number.uint32Value)
        ),
        scale: screen.backingScaleFactor
      )
    }
    let fallbackFrame = NSScreen.main?.frame ?? .zero
    let union =
      screens
      .map(\.appKitFrame)
      .reduce(fallbackFrame) { $0.union($1) }
    return ScreenLayout(
      screens: screens,
      appKitUnionFrame: union,
      maximumScale: screens.map(\.scale).max() ?? 2
    )
  }

  func localPoint(for point: GesturePoint) -> CGPoint {
    let quartzPoint = CGPoint(
      x: CGFloat(point.x),
      y: CGFloat(point.y)
    )
    if let screen = screens.first(where: {
      $0.quartzFrame.contains(quartzPoint)
    }) {
      let appKitPoint = CGPoint(
        x: screen.appKitFrame.minX
          + quartzPoint.x
          - screen.quartzFrame.minX,
        y: screen.appKitFrame.maxY
          - quartzPoint.y
          + screen.quartzFrame.minY
      )
      return CGPoint(
        x: appKitPoint.x - appKitUnionFrame.minX,
        y: appKitPoint.y - appKitUnionFrame.minY
      )
    }

    return CGPoint(
      x: quartzPoint.x - appKitUnionFrame.minX,
      y: appKitUnionFrame.maxY - quartzPoint.y
    )
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
