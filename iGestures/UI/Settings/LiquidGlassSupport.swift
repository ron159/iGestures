import AppKit
import SwiftUI

enum LiquidGlassStyle {
  static var isAvailable: Bool {
    if #available(macOS 26.0, *) {
      return true
    } else {
      return false
    }
  }

  static var supportsInteractiveEffect: Bool {
    if #available(macOS 27.0, *) {
      return true
    } else {
      return false
    }
  }
}

struct AdaptiveGlassGroup<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder let content: () -> Content

  init(
    spacing: CGFloat = 8,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.spacing = spacing
    self.content = content
  }

  @ViewBuilder
  var body: some View {
    if #available(macOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) {
        content()
      }
    } else {
      content()
    }
  }
}

private struct AdaptiveWindowFocusOpacityModifier: ViewModifier {
  @Environment(\.appearsActive) private var appearsActive
  let inactiveOpacity: Double

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .opacity(appearsActive ? 1 : inactiveOpacity)
        .animation(.easeInOut(duration: 0.18), value: appearsActive)
    } else {
      content
    }
  }
}

extension View {
  @ViewBuilder
  func adaptiveGlassCard(
    cornerRadius: CGFloat = 14,
    tint: Color? = nil,
    interactive: Bool = false
  ) -> some View {
    if #available(macOS 26.0, *) {
      self.glassEffect(
        resolvedGlass(tint: tint, interactive: interactive),
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
    } else {
      let fallbackRadius = min(cornerRadius, 10)
      self
        .background(
          Color(nsColor: .controlBackgroundColor),
          in: RoundedRectangle(cornerRadius: fallbackRadius, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: fallbackRadius, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
  }

  @ViewBuilder
  func adaptiveGlassCapsule(
    tint: Color? = nil,
    interactive: Bool = false
  ) -> some View {
    if #available(macOS 26.0, *) {
      self.glassEffect(
        resolvedGlass(tint: tint, interactive: interactive),
        in: Capsule()
      )
    } else {
      self
        .background(.regularMaterial, in: Capsule())
        .overlay {
          Capsule()
            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }
  }

  @ViewBuilder
  func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
    if #available(macOS 26.0, *) {
      if prominent {
        self.buttonStyle(.glassProminent)
      } else {
        self.buttonStyle(.glass)
      }
    } else {
      if prominent {
        self.buttonStyle(.borderedProminent)
      } else {
        self.buttonStyle(.bordered)
      }
    }
  }

  func adaptiveWindowFocusOpacity(inactive: Double = 0.72) -> some View {
    modifier(AdaptiveWindowFocusOpacityModifier(inactiveOpacity: inactive))
  }

  @available(macOS 26.0, *)
  private func resolvedGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint {
      glass = glass.tint(tint)
    }
    if interactive {
      glass = glass.interactive(true)
    }
    return glass
  }
}

enum LuminousTrailGeometry {
  struct RibbonPaths {
    let glowPath: CGPath
    let bodyPath: CGPath
    let corePath: CGPath
    let headPoint: CGPoint?
    let headRadius: CGFloat
  }

  static func trimmedPoints(_ points: [CGPoint], progress: CGFloat) -> [CGPoint] {
    let clamped = min(max(progress, 0), 1)
    guard !points.isEmpty, clamped > 0 else { return [] }
    guard clamped < 1, points.count > 1 else { return points }

    var lengths: [CGFloat] = [0]
    lengths.reserveCapacity(points.count)
    var total: CGFloat = 0
    for i in 1..<points.count {
      total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
      lengths.append(total)
    }
    guard total > 0.001 else { return [points[0]] }

    let target = total * clamped
    var result: [CGPoint] = [points[0]]
    for i in 1..<points.count {
      if lengths[i] < target {
        result.append(points[i])
      } else {
        let segLen = lengths[i] - lengths[i - 1]
        if segLen > 0.001 {
          let ratio = (target - lengths[i - 1]) / segLen
          let p0 = points[i - 1]
          let p1 = points[i]
          result.append(
            CGPoint(
              x: p0.x + (p1.x - p0.x) * ratio,
              y: p0.y + (p1.y - p0.y) * ratio
            )
          )
        }
        break
      }
    }
    return result
  }

  static func buildRibbon(from rawPoints: [CGPoint], maxRadius: CGFloat) -> RibbonPaths {
    let points = smoothedPoints(rawPoints)
    let glowPath = CGMutablePath()
    let bodyPath = CGMutablePath()
    let corePath = CGMutablePath()

    guard let first = points.first else {
      return RibbonPaths(
        glowPath: glowPath,
        bodyPath: bodyPath,
        corePath: corePath,
        headPoint: nil,
        headRadius: maxRadius
      )
    }

    var cumDist: [CGFloat] = [0]
    cumDist.reserveCapacity(points.count)
    var totalLength: CGFloat = 0
    for i in 1..<points.count {
      totalLength += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
      cumDist.append(totalLength)
    }

    if points.count == 1 || totalLength < 0.05 {
      let bodyRadius = max(1.6, maxRadius * 0.85)
      let coreRadius = max(0.8, bodyRadius * 0.46)
      let glowRadius = max(2.2, maxRadius * 1.45)
      addCCWCircle(to: glowPath, center: first, radius: glowRadius)
      addCCWCircle(to: bodyPath, center: first, radius: bodyRadius)
      addCCWCircle(to: corePath, center: first, radius: coreRadius)
      return RibbonPaths(
        glowPath: glowPath,
        bodyPath: bodyPath,
        corePath: corePath,
        headPoint: points.last ?? first,
        headRadius: maxRadius
      )
    }

    func bodyRadius(at t: CGFloat) -> CGFloat {
      let progress = sin(t * (.pi / 2))
      return max(1.4, maxRadius * (0.78 + 0.22 * progress))
    }

    func coreRadius(at t: CGFloat) -> CGFloat {
      max(0.7, bodyRadius(at: t) * 0.45)
    }

    func glowRadius(at t: CGFloat) -> CGFloat {
      max(2.2, bodyRadius(at: t) * 1.55)
    }

    var start = 0
    while start < points.count - 1 {
      let end = endOfStraightRun(in: points, from: start)
      let t0 = cumDist[start] / totalLength
      let t1 = cumDist[end] / totalLength
      let p0 = points[start]
      let p1 = points[end]
      start = end

      addCCWCapsule(
        to: glowPath,
        from: p0,
        r0: glowRadius(at: t0),
        to: p1,
        r1: glowRadius(at: t1)
      )
      addCCWCapsule(
        to: bodyPath,
        from: p0,
        r0: bodyRadius(at: t0),
        to: p1,
        r1: bodyRadius(at: t1)
      )
      addCCWCapsule(
        to: corePath,
        from: p0,
        r0: coreRadius(at: t0),
        to: p1,
        r1: coreRadius(at: t1)
      )
    }

    return RibbonPaths(
      glowPath: glowPath,
      bodyPath: bodyPath,
      corePath: corePath,
      headPoint: points.last,
      headRadius: maxRadius
    )
  }

  // Anchor each run to its first segment so appending samples cannot reselect old corners.
  private static func endOfStraightRun(in points: [CGPoint], from start: Int) -> Int {
    let origin = points[start]
    var end = start + 1
    let dx = points[end].x - origin.x
    let dy = points[end].y - origin.y
    let length = hypot(dx, dy)
    guard length > 0 else { return end }

    let ux = dx / length
    let uy = dy / length
    var previousProjection = length
    // Limit the span so the ribbon's gradual width change is preserved on long straight runs.
    while end + 1 < points.count && end - start < 32 {
      let x = points[end + 1].x - origin.x
      let y = points[end + 1].y - origin.y
      let projection = x * ux + y * uy
      guard projection >= previousProjection, abs(x * uy - y * ux) <= 0.2 else { break }
      previousProjection = projection
      end += 1
    }
    return end
  }

  private static func smoothedPoints(_ rawPoints: [CGPoint]) -> [CGPoint] {
    guard rawPoints.count > 2 else { return rawPoints }

    var spaced: [CGPoint] = []
    spaced.reserveCapacity(rawPoints.count)
    if let first = rawPoints.first {
      spaced.append(first)
    }
    let minStepSq: CGFloat = 1.44
    for i in 1..<(rawPoints.count - 1) {
      let pt = rawPoints[i]
      if let last = spaced.last {
        let dx = pt.x - last.x
        let dy = pt.y - last.y
        if dx * dx + dy * dy >= minStepSq {
          spaced.append(pt)
        }
      }
    }
    if let last = rawPoints.last {
      spaced.append(last)
    }

    guard spaced.count >= 3 else { return spaced }

    var smoothed: [CGPoint] = []
    smoothed.reserveCapacity(spaced.count)
    smoothed.append(spaced[0])
    for i in 0..<(spaced.count - 1) {
      let p0 = spaced[i]
      let p1 = spaced[i + 1]
      let segLen = hypot(p1.x - p0.x, p1.y - p0.y)
      if segLen > 3.0 {
        smoothed.append(
          CGPoint(
            x: 0.75 * p0.x + 0.25 * p1.x,
            y: 0.75 * p0.y + 0.25 * p1.y
          )
        )
        smoothed.append(
          CGPoint(
            x: 0.25 * p0.x + 0.75 * p1.x,
            y: 0.25 * p0.y + 0.75 * p1.y
          )
        )
      } else {
        smoothed.append(p1)
      }
    }
    if let last = spaced.last, smoothed.last != last {
      smoothed.append(last)
    }
    return smoothed
  }

  private static func addCCWCircle(
    to path: CGMutablePath,
    center: CGPoint,
    radius: CGFloat
  ) {
    guard radius > 0 else { return }
    path.addArc(
      center: center,
      radius: radius,
      startAngle: 0,
      endAngle: .pi * 2,
      clockwise: false
    )
    path.closeSubpath()
  }

  private static func addCCWCapsule(
    to path: CGMutablePath,
    from p0: CGPoint,
    r0: CGFloat,
    to p1: CGPoint,
    r1: CGFloat
  ) {
    let dx = p1.x - p0.x
    let dy = p1.y - p0.y
    let dist = hypot(dx, dy)
    let diff = r0 - r1

    if dist <= abs(diff) + 0.001 {
      if r0 >= r1 {
        addCCWCircle(to: path, center: p0, radius: r0)
      } else {
        addCCWCircle(to: path, center: p1, radius: r1)
      }
      return
    }

    let baseAngle = atan2(dy, dx)
    let cosAlpha = min(1, max(-1, diff / dist))
    let alpha = acos(cosAlpha)
    let anglePlus = baseAngle + alpha
    let angleMinus = baseAngle - alpha

    let t0Plus = CGPoint(
      x: p0.x + r0 * cos(anglePlus),
      y: p0.y + r0 * sin(anglePlus)
    )
    let t1Minus = CGPoint(
      x: p1.x + r1 * cos(angleMinus),
      y: p1.y + r1 * sin(angleMinus)
    )

    path.move(to: t0Plus)
    path.addArc(
      center: p0,
      radius: r0,
      startAngle: anglePlus,
      endAngle: angleMinus,
      clockwise: false
    )
    path.addLine(to: t1Minus)
    path.addArc(
      center: p1,
      radius: r1,
      startAngle: angleMinus,
      endAngle: anglePlus,
      clockwise: false
    )
    path.closeSubpath()
  }
}

enum LuminousCanvasTrail {
  static func draw(
    in context: inout GraphicsContext,
    points: [CGPoint],
    color: Color,
    maxRadius: CGFloat = 2.6,
    glowBlurRadius: CGFloat = 5.5,
    showsMarkers: Bool = false,
    markerSize: CGFloat = 10,
    showsLiveHead: Bool = true
  ) {
    guard let first = points.first else { return }

    let ribbon = LuminousTrailGeometry.buildRibbon(from: points, maxRadius: maxRadius)
    let glowSwiftUIPath = Path(ribbon.glowPath)
    let bodySwiftUIPath = Path(ribbon.bodyPath)
    let coreSwiftUIPath = Path(ribbon.corePath)
    let nonZero = FillStyle(eoFill: false)

    context.drawLayer { glowContext in
      glowContext.addFilter(.blur(radius: glowBlurRadius))
      glowContext.fill(glowSwiftUIPath, with: .color(color.opacity(0.50)), style: nonZero)
    }

    context.fill(bodySwiftUIPath, with: .color(color.opacity(0.95)), style: nonZero)
    context.fill(coreSwiftUIPath, with: .color(.white.opacity(0.90)), style: nonZero)

    if showsLiveHead, let head = ribbon.headPoint {
      let haloR = maxRadius * 1.5
      let haloPath = Path(
        ellipseIn: CGRect(
          x: head.x - haloR,
          y: head.y - haloR,
          width: haloR * 2,
          height: haloR * 2
        )
      )
      context.drawLayer { headGlow in
        headGlow.addFilter(.blur(radius: max(3, glowBlurRadius * 0.75)))
        headGlow.fill(haloPath, with: .color(color.opacity(0.65)))
      }

      let coreR = max(1.2, maxRadius * 0.55)
      let headCorePath = Path(
        ellipseIn: CGRect(
          x: head.x - coreR,
          y: head.y - coreR,
          width: coreR * 2,
          height: coreR * 2
        )
      )
      context.fill(headCorePath, with: .color(.white.opacity(0.96)))
    }

    if showsMarkers {
      let startMarker = Path(
        ellipseIn: CGRect(
          x: first.x - markerSize / 2,
          y: first.y - markerSize / 2,
          width: markerSize,
          height: markerSize
        )
      )
      context.drawLayer { markerGlow in
        markerGlow.addFilter(.blur(radius: max(2.5, glowBlurRadius * 0.55)))
        markerGlow.fill(startMarker, with: .color(color.opacity(0.5)))
        if let last = points.last {
          let endGlow = Path(
            ellipseIn: CGRect(
              x: last.x - markerSize / 2,
              y: last.y - markerSize / 2,
              width: markerSize,
              height: markerSize
            )
          )
          markerGlow.fill(endGlow, with: .color(color.opacity(0.55)))
        }
      }
      context.fill(startMarker, with: .color(.white.opacity(0.94)))
      context.stroke(startMarker, with: .color(color.opacity(0.85)), lineWidth: 1.5)

      if let last = points.last {
        let endMarker = Path(
          ellipseIn: CGRect(
            x: last.x - markerSize / 2,
            y: last.y - markerSize / 2,
            width: markerSize,
            height: markerSize
          )
        )
        context.fill(endMarker, with: .color(color))
        context.stroke(endMarker, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
      }
    }
  }
}
