import AppKit
import SwiftUI

@main
struct IGesturesApp: App {
  @StateObject private var model: AppModel
  @StateObject private var settingsWindowController: SettingsWindowController

  init() {
    let model = AppModel()
    _model = StateObject(wrappedValue: model)
    _settingsWindowController = StateObject(
      wrappedValue: SettingsWindowController(model: model)
    )
  }

  var body: some Scene {
    #if UI_PREVIEW
      WindowGroup("iGestures UI Preview", id: "ui-preview") {
        PreviewSettingsHost(model: model)
      }
      .defaultSize(width: 1_100, height: 700)
      .windowResizability(.contentMinSize)
    #endif

    MenuBarExtra {
      MenuBarContent(
        model: model,
        showSettings: settingsWindowController.showSettings
      )
    } label: {
      MenuBarIcon(isEnabled: model.isEnabled)
        .accessibilityLabel("iGestures")
    }
    #if !UI_PREVIEW
      .commands {
        AppSettingsCommands(
          showSettings: settingsWindowController.showSettings
        )
      }
    #endif

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

#if !UI_PREVIEW
  private struct AppSettingsCommands: Commands {
    let showSettings: () -> Void

    var body: some Commands {
      CommandGroup(replacing: .appSettings) {
        Button(
          String(localized: "Settings…"),
          action: showSettings
        )
        .keyboardShortcut(",", modifiers: .command)
      }
    }
  }
#endif

@MainActor
private final class SettingsWindowController: ObservableObject {
  private let model: AppModel
  private var windowController: NSWindowController?

  init(model: AppModel) {
    self.model = model
  }

  func showSettings() {
    let windowController =
      windowController ?? makeWindowController()
    self.windowController = windowController
    NSApp.activate()
    windowController.showWindow(nil)
    windowController.window?.makeKeyAndOrderFront(nil)
  }

  private func makeWindowController() -> NSWindowController {
    let hostingController = NSHostingController(
      rootView: SettingsRootView(model: model)
    )
    let window = NSWindow(
      contentRect: NSRect(
        origin: .zero,
        size: NSSize(width: 1_100, height: 700)
      ),
      styleMask: [
        .titled,
        .closable,
        .miniaturizable,
        .resizable,
      ],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    window.title = "iGestures"
    window.contentMinSize = SettingsRootView.minimumContentSize
    window.isReleasedWhenClosed = false
    window.center()
    window.setFrameAutosaveName("iGestures.SettingsWindow")
    return NSWindowController(window: window)
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
    let image =
      NSImage(named: "MenuBarHamsterTemplate")
      ?? NSImage(
        systemSymbolName: "pawprint.fill",
        accessibilityDescription: nil
      )
      ?? NSImage(size: NSSize(width: 22, height: 18))
    image.size = NSSize(width: 22, height: 18)
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
        String(localized: "Gesture Trigger"),
        selection: Binding(
          get: { model.triggerButton },
          set: { model.setTriggerButton($0) }
        )
      ) {
        ForEach(GestureTriggerButton.commonPresets) { button in
          Text(onboardingTriggerLabel(button)).tag(button)
        }
        if !GestureTriggerButton.commonPresets.contains(
          model.triggerButton
        ) {
          Text(onboardingTriggerLabel(model.triggerButton))
            .tag(model.triggerButton)
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
    button.localizedName
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
  let showSettings: () -> Void

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

    Button(
      String(localized: "Settings…"),
      action: showSettings
    )

    Divider()

    Button(String(localized: "Quit")) {
      model.terminate()
    }
  }

  private func onboardingMenuTriggerLabel(
    _ button: GestureTriggerButton
  ) -> String {
    button.localizedName
  }
}
