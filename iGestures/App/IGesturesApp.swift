import AppKit
import SwiftUI

@main
struct IGesturesApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    #if UI_PREVIEW
      WindowGroup("iGestures UI Preview", id: "ui-preview") {
        PreviewSettingsHost(model: model)
      }
      .defaultSize(width: 1_100, height: 700)
      .windowResizability(.contentMinSize)
    #endif

    MenuBarExtra {
      MenuBarContent(model: model)
    } label: {
      MenuBarIcon(isEnabled: model.isEnabled)
        .accessibilityLabel("iGestures")
    }

    Settings {
      SettingsRootView(model: model)
    }
    .defaultSize(width: 1_100, height: 700)
    .windowResizability(.contentMinSize)

    #if !UI_PREVIEW
      Window(
        String(localized: "Welcome to iGestures"),
        id: "onboarding"
      ) {
        OnboardingView(model: model)
      }
      .defaultSize(width: 660, height: 560)
    #endif
  }
}

#if UI_PREVIEW
  private struct PreviewSettingsHost: View {
    @ObservedObject var model: AppModel
    @State private var didPrepareSampleGestures = false

    var body: some View {
      SettingsRootView(model: model)
        .onChange(
          of: model.isLoadingMappings,
          initial: true
        ) {
          prepareSampleGesturesIfNeeded()
        }
    }

    private func prepareSampleGesturesIfNeeded() {
      guard !model.isLoadingMappings,
        !didPrepareSampleGestures
      else {
        return
      }

      didPrepareSampleGestures = true
      if model.mappings.isEmpty {
        model.installPresets(GesturePresetLibrary.builtIn)
      }
    }
  }
#endif

private struct MenuBarIcon: View {
  let isEnabled: Bool

  var body: some View {
    Image(nsImage: MenuBarTemplateImage.icon)
      .renderingMode(.template)
      .frame(width: 22, height: 18)
      .opacity(isEnabled ? 1 : 0.82)
  }
}

private enum MenuBarTemplateImage {
  static let icon = make()

  private static func make() -> NSImage {
    let image = NSImage(
      size: NSSize(width: 22, height: 18),
      flipped: true
    ) { _ in
      NSColor.black.setStroke()
      NSColor.black.setFill()

      func stroke(_ path: NSBezierPath, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
      }

      let tail = NSBezierPath()
      tail.move(to: NSPoint(x: 18.4, y: 15.5))
      tail.curve(
        to: NSPoint(x: 20.7, y: 15.1),
        controlPoint1: NSPoint(x: 19.5, y: 14.5),
        controlPoint2: NSPoint(x: 20.7, y: 14.6)
      )
      tail.curve(
        to: NSPoint(x: 18.1, y: 16.7),
        controlPoint1: NSPoint(x: 21.3, y: 16.1),
        controlPoint2: NSPoint(x: 19.7, y: 17.2)
      )
      stroke(tail, width: 1.15)

      let rearEar = NSBezierPath()
      rearEar.move(to: NSPoint(x: 4.3, y: 4.2))
      rearEar.curve(
        to: NSPoint(x: 4.7, y: 1.8),
        controlPoint1: NSPoint(x: 4.2, y: 3.1),
        controlPoint2: NSPoint(x: 4.2, y: 2.3)
      )
      rearEar.curve(
        to: NSPoint(x: 7.6, y: 3.5),
        controlPoint1: NSPoint(x: 6.2, y: 1),
        controlPoint2: NSPoint(x: 7.4, y: 2)
      )
      stroke(rearEar, width: 1.15)

      let outline = NSBezierPath()
      outline.move(to: NSPoint(x: 7.6, y: 3.6))
      outline.curve(
        to: NSPoint(x: 1.6, y: 7.9),
        controlPoint1: NSPoint(x: 4.7, y: 3.5),
        controlPoint2: NSPoint(x: 2.2, y: 5.4)
      )
      outline.curve(
        to: NSPoint(x: 3.2, y: 10.9),
        controlPoint1: NSPoint(x: 1.2, y: 9.3),
        controlPoint2: NSPoint(x: 2, y: 10.4)
      )
      outline.curve(
        to: NSPoint(x: 5.3, y: 11.6),
        controlPoint1: NSPoint(x: 3.9, y: 11.4),
        controlPoint2: NSPoint(x: 4.7, y: 11.6)
      )
      outline.curve(
        to: NSPoint(x: 7.4, y: 15.9),
        controlPoint1: NSPoint(x: 5.1, y: 13.7),
        controlPoint2: NSPoint(x: 6.1, y: 15.1)
      )
      outline.curve(
        to: NSPoint(x: 9.1, y: 16.7),
        controlPoint1: NSPoint(x: 6.7, y: 16.3),
        controlPoint2: NSPoint(x: 7.4, y: 16.7)
      )
      outline.line(to: NSPoint(x: 17.1, y: 16.7))
      outline.curve(
        to: NSPoint(x: 20.2, y: 13.2),
        controlPoint1: NSPoint(x: 19.2, y: 16.7),
        controlPoint2: NSPoint(x: 20.2, y: 15.5)
      )
      outline.curve(
        to: NSPoint(x: 17.8, y: 8),
        controlPoint1: NSPoint(x: 20.1, y: 10.7),
        controlPoint2: NSPoint(x: 19.2, y: 9)
      )
      outline.curve(
        to: NSPoint(x: 10.9, y: 3.6),
        controlPoint1: NSPoint(x: 15.2, y: 6.1),
        controlPoint2: NSPoint(x: 12.8, y: 5.2)
      )
      stroke(outline, width: 1.2)

      let frontEar = NSBezierPath()
      frontEar.move(to: NSPoint(x: 7.5, y: 4.1))
      frontEar.curve(
        to: NSPoint(x: 8.1, y: 1.6),
        controlPoint1: NSPoint(x: 7.6, y: 3),
        controlPoint2: NSPoint(x: 7.7, y: 2.1)
      )
      frontEar.curve(
        to: NSPoint(x: 10.8, y: 1.8),
        controlPoint1: NSPoint(x: 9.2, y: 0.9),
        controlPoint2: NSPoint(x: 10.5, y: 1.1)
      )
      frontEar.curve(
        to: NSPoint(x: 9.5, y: 5.4),
        controlPoint1: NSPoint(x: 12.1, y: 3.4),
        controlPoint2: NSPoint(x: 10.9, y: 5)
      )
      stroke(frontEar, width: 1.15)

      NSBezierPath(
        ovalIn: NSRect(x: 3.8, y: 6.1, width: 1.55, height: 1.8)
      ).fill()
      NSBezierPath(
        ovalIn: NSRect(x: 1.05, y: 8, width: 1.15, height: 0.85)
      ).fill()

      let faceDetails = NSBezierPath()
      faceDetails.move(to: NSPoint(x: 2, y: 9))
      faceDetails.curve(
        to: NSPoint(x: 3.6, y: 9.4),
        controlPoint1: NSPoint(x: 2.2, y: 9.8),
        controlPoint2: NSPoint(x: 3, y: 9.8)
      )
      faceDetails.move(to: NSPoint(x: 3.8, y: 8.7))
      faceDetails.curve(
        to: NSPoint(x: 6.6, y: 8.5),
        controlPoint1: NSPoint(x: 4.8, y: 8.4),
        controlPoint2: NSPoint(x: 5.8, y: 8.4)
      )
      faceDetails.move(to: NSPoint(x: 3.8, y: 9.35))
      faceDetails.curve(
        to: NSPoint(x: 6.4, y: 10),
        controlPoint1: NSPoint(x: 4.7, y: 9.4),
        controlPoint2: NSPoint(x: 5.7, y: 9.7)
      )
      stroke(faceDetails, width: 0.65)

      let forepaws = NSBezierPath()
      forepaws.move(to: NSPoint(x: 8.6, y: 12.2))
      forepaws.curve(
        to: NSPoint(x: 7, y: 14.2),
        controlPoint1: NSPoint(x: 7.5, y: 12.9),
        controlPoint2: NSPoint(x: 7, y: 13.6)
      )
      forepaws.curve(
        to: NSPoint(x: 7.7, y: 14.6),
        controlPoint1: NSPoint(x: 6.9, y: 14.7),
        controlPoint2: NSPoint(x: 7.3, y: 14.8)
      )
      forepaws.curve(
        to: NSPoint(x: 8.3, y: 13.9),
        controlPoint1: NSPoint(x: 8, y: 14.4),
        controlPoint2: NSPoint(x: 8.1, y: 14.1)
      )
      forepaws.move(to: NSPoint(x: 7.7, y: 14.6))
      forepaws.curve(
        to: NSPoint(x: 8.9, y: 13.9),
        controlPoint1: NSPoint(x: 8.2, y: 15),
        controlPoint2: NSPoint(x: 8.6, y: 14.4)
      )
      stroke(forepaws, width: 0.8)

      let hindLeg = NSBezierPath()
      hindLeg.move(to: NSPoint(x: 15.7, y: 11.5))
      hindLeg.curve(
        to: NSPoint(x: 14.6, y: 16.5),
        controlPoint1: NSPoint(x: 13.8, y: 12.8),
        controlPoint2: NSPoint(x: 13.5, y: 15)
      )
      stroke(hindLeg, width: 0.85)

      return true
    }
    image.isTemplate = true
    return image
  }
}

private struct OnboardingView: View {
  @Environment(\.dismissWindow) private var dismissWindow
  @ObservedObject var model: AppModel

  @State private var step = 0
  @State private var selectedPresetIDs: Set<UUID> = []
  @State private var practiceSucceeded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text(String(localized: "Welcome to iGestures"))
          .font(.largeTitle)
          .fontWeight(.bold)
        Spacer()
        Text("\(step + 1) / 4")
          .foregroundStyle(.secondary)
      }

      Group {
        switch step {
        case 0:
          permissionStep
        case 1:
          triggerStep
        case 2:
          presetStep
        default:
          practiceStep
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      HStack {
        Button(String(localized: "Skip Setup")) {
          complete()
        }
        Spacer()
        if step > 0 {
          Button(String(localized: "Back")) {
            step -= 1
          }
        }
        if step < 3 {
          Button(String(localized: "Continue")) {
            step += 1
          }
          .keyboardShortcut(.defaultAction)
        } else {
          Button(String(localized: "Finish")) {
            model.installPresets(selectedPresets)
            complete()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!practiceSucceeded)
        }
      }
    }
    .padding(28)
    .onAppear {
      if !model.isOnboardingPresented {
        dismissWindow(id: "onboarding")
      }
    }
  }

  private var permissionStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(
        String(localized: "Required Permissions"),
        systemImage: "hand.raised.fill"
      )
      .font(.title2)

      Text(
        String(
          localized:
            "iGestures observes the configured mouse button and posts only the action you choose. Gesture paths stay on this Mac."
        )
      )

      Text(
        String(
          localized:
            "macOS shows the required permission prompts only after you choose Grant Access."
        )
      )
      .foregroundStyle(.secondary)

      HStack {
        Button(String(localized: "Grant Access")) {
          model.requestAccess()
        }
        .disabled(!model.canRequestAccess)
        Text(model.permissionStatusText)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var triggerStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(
        String(localized: "Choose a Trigger Button"),
        systemImage: "computermouse"
      )
      .font(.title2)

      Text(
        String(
          localized:
            "Hold this button and draw. A normal click is replayed when no gesture starts."
        )
      )

      Picker(
        String(localized: "Trigger Mouse Button"),
        selection: Binding(
          get: { model.triggerButton },
          set: { model.setTriggerButton($0) }
        )
      ) {
        ForEach(GestureTriggerButton.commonPresets) { button in
          Text(onboardingTriggerLabel(button)).tag(button)
        }
      }
      .pickerStyle(.radioGroup)
    }
  }

  private var presetStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(
        String(localized: "Choose Starter Gestures"),
        systemImage: "square.grid.2x2"
      )
      .font(.title2)

      Text(
        String(
          localized:
            "These are copied into your library and can be disabled, duplicated, or changed later."
        )
      )
      .foregroundStyle(.secondary)

      List(GesturePresetLibrary.builtIn) { preset in
        Toggle(
          isOn: Binding(
            get: { selectedPresetIDs.contains(preset.id) },
            set: {
              if $0 {
                selectedPresetIDs.insert(preset.id)
              } else {
                selectedPresetIDs.remove(preset.id)
              }
            }
          )
        ) {
          HStack {
            GestureTemplatePreview(template: preset.template)
              .frame(width: 48, height: 36)
            VStack(alignment: .leading) {
              Text(preset.name)
              Text(GestureActionSummary.text(for: preset.action))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .listStyle(.inset)
    }
  }

  private var practiceStep: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(
        String(localized: "Practice"),
        systemImage: "checkmark.circle"
      )
      .font(.title2)

      Text(
        String(
          format: String(
            localized: "Draw “%@” in the practice area."
          ),
          practicePreset.name
        )
      )

      HStack(spacing: 18) {
        GestureTemplatePreview(template: practicePreset.template)
          .frame(width: 110, height: 110)
        GesturePracticePad(
          template: practicePreset.template,
          succeeded: $practiceSucceeded
        )
        .frame(height: 250)
      }
    }
  }

  private var selectedPresets: [GesturePreset] {
    GesturePresetLibrary.builtIn.filter {
      selectedPresetIDs.contains($0.id)
    }
  }

  private var practicePreset: GesturePreset {
    selectedPresets.first
      ?? GesturePresetLibrary.builtIn[0]
  }

  private func complete() {
    model.finishOnboarding()
    dismissWindow(id: "onboarding")
  }

  private func onboardingTriggerLabel(
    _ button: GestureTriggerButton
  ) -> String {
    switch button.buttonNumber {
    case 1:
      String(localized: "Right Mouse Button")
    case 2:
      String(localized: "Middle Mouse Button")
    default:
      String(
        format: String(localized: "Mouse Button %d"),
        Int(button.buttonNumber) + 1
      )
    }
  }
}

struct GesturePracticePad: View {
  let template: GestureTemplate
  @Binding var succeeded: Bool
  @State private var points: [GesturePoint] = []
  @State private var message = String(
    localized: "Draw here without executing an action."
  )

  var body: some View {
    Canvas { context, size in
      let bounds = Path(
        roundedRect: CGRect(origin: .zero, size: size),
        cornerRadius: 10
      )
      context.fill(bounds, with: .color(.secondary.opacity(0.08)))
      guard let first = points.first else { return }
      var path = Path()
      path.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
      for point in points.dropFirst() {
        path.addLine(
          to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
        )
      }
      context.stroke(
        path,
        with: .color(succeeded ? .green : .accentColor),
        style: StrokeStyle(
          lineWidth: 4,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged {
          points.append(
            GesturePoint(
              x: Float($0.location.x),
              y: Float($0.location.y)
            )
          )
        }
        .onEnded { _ in
          validate()
        }
    )
    .overlay(alignment: .bottom) {
      Text(message)
        .font(.callout)
        .padding(8)
    }
  }

  private func validate() {
    defer {
      if !succeeded {
        points.removeAll(keepingCapacity: true)
      }
    }
    guard let candidate = try? GestureNormalizer().normalize(points)
    else {
      message = String(localized: "Try a longer, clearer stroke.")
      return
    }
    let distance = GestureRecognizer().distance(
      from: candidate,
      to: template
    )
    succeeded =
      distance
      <= GestureRecognizer().configuration.acceptanceThreshold
    message =
      succeeded
      ? String(localized: "Practice passed.")
      : String(localized: "Not quite. Follow the preview and try again.")
  }
}

private struct MenuBarContent: View {
  @ObservedObject var model: AppModel
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button(
      model.isEnabled
        ? String(localized: "Disable")
        : String(localized: "Enable")
    ) {
      model.toggleEnabled()
    }

    if let applicationName = model.currentApplicationName {
      Button(
        model.isCurrentApplicationExcluded
          ? String(
            format: String(localized: "Enable in %@"),
            applicationName
          )
          : String(
            format: String(localized: "Exclude %@"),
            applicationName
          )
      ) {
        model.setCurrentApplicationExcluded(
          !model.isCurrentApplicationExcluded
        )
      }

      Menu(String(localized: "Exclude Current App for Trigger")) {
        ForEach(GestureTriggerButton.commonPresets) { button in
          Button(onboardingMenuTriggerLabel(button)) {
            model.setCurrentApplicationExcluded(
              true,
              triggerButton: button
            )
          }
        }
      }
    }

    Divider()

    Text(model.permissionStatusText)

    Button(String(localized: "Settings…")) {
      showSettings()
    }

    Divider()

    Button(String(localized: "Quit")) {
      model.terminate()
    }
  }

  private func showSettings() {
    NSApp.activate()
    openSettings()
    raiseSettingsWindow()
    Task { @MainActor in
      await Task.yield()
      raiseSettingsWindow()
    }
  }

  private func raiseSettingsWindow() {
    guard
      let window = NSApp.windows.first(where: {
        $0.canBecomeKey && $0.styleMask.contains(.titled)
      })
    else {
      return
    }
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  private func onboardingMenuTriggerLabel(
    _ button: GestureTriggerButton
  ) -> String {
    switch button.buttonNumber {
    case 1:
      String(localized: "Right Mouse Button")
    case 2:
      String(localized: "Middle Mouse Button")
    default:
      String(
        format: String(localized: "Mouse Button %d"),
        Int(button.buttonNumber) + 1
      )
    }
  }
}
