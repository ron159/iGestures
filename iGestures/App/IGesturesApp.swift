import AppIntents
import AppKit
import Combine
import SwiftUI

@main
struct IGesturesApp: App {
  #if !UI_PREVIEW
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #endif
  @StateObject private var model: AppModel
  @StateObject private var settingsWindowController: SettingsWindowController

  init() {
    let model = AppModel()
    _model = StateObject(wrappedValue: model)
    let settingsController = SettingsWindowController(model: model)
    _settingsWindowController = StateObject(wrappedValue: settingsController)
    #if !UI_PREVIEW
      AppDelegate.configure(
        model: model,
        settingsController: settingsController
      )
    #endif
  }

  var body: some Scene {
    #if UI_PREVIEW
      WindowGroup("iGestures UI Preview", id: "ui-preview") {
        PreviewSettingsHost(model: model)
      }
      .defaultSize(width: 1_100, height: 700)
      .windowResizability(.contentMinSize)
    #else
      Settings {
        EmptyView()
      }
      .commands {
        AppSettingsCommands(
          showSettings: settingsWindowController.showSettings
        )
      }
    #endif
  }
}

extension InterfaceAppearance {
  var preferredColorScheme: ColorScheme? {
    switch self {
    case .system:
      nil
    case .light:
      .light
    case .dark:
      .dark
    }
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

#if !UI_PREVIEW
  @MainActor
  private final class AppDelegate: NSObject, NSApplicationDelegate {
    private static weak var sharedInstance: AppDelegate?
    private static weak var model: AppModel?
    private static weak var settingsController: SettingsWindowController?

    private var statusBarController: StatusBarController?
    private var didFinishLaunching = false

    static func configure(
      model: AppModel,
      settingsController: SettingsWindowController
    ) {
      self.model = model
      self.settingsController = settingsController
      if let instance = sharedInstance, instance.didFinishLaunching {
        instance.installStatusBarIfNeeded()
      }
    }

    override init() {
      super.init()
      Self.sharedInstance = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
      didFinishLaunching = true
      installStatusBarIfNeeded()
      #if DEBUG
        DispatchQueue.main.async { Self.settingsController?.showSettings() }
      #endif
    }

    func applicationShouldHandleReopen(
      _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
      statusBarController?.ensureVisible()
      Self.settingsController?.showSettings()
      return true
    }

    private func installStatusBarIfNeeded() {
      guard statusBarController == nil,
        let model = Self.model,
        let settingsController = Self.settingsController
      else {
        return
      }
      statusBarController = StatusBarController(
        model: model,
        showSettings: settingsController.showSettings,
        showGestureHelp: settingsController.showGestureHelp
      )
    }
  }
#endif

@MainActor
private final class SettingsWindowController:
  NSObject, ObservableObject, NSWindowDelegate
{
  private let model: AppModel
  private var windowController: NSWindowController?
  private var helpWindowController: NSWindowController?
  private var onboardingWindowController: NSWindowController?
  private var cancellables: Set<AnyCancellable> = []

  init(model: AppModel) {
    self.model = model
    super.init()
    model.showGestureHelp = { [weak self] in self?.showGestureHelp() }
    model.$isOnboardingPresented
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] isPresented in
        if isPresented {
          self?.showOnboarding()
        } else {
          self?.closeOnboarding()
        }
      }
      .store(in: &cancellables)
  }

  func showOnboarding() {
    if onboardingWindowController == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.title = String(localized: "Welcome to iGestures")
      window.contentViewController = NSHostingController(
        rootView: OnboardingView(model: model)
          .preferredColorScheme(model.interfaceAppearance.preferredColorScheme)
      )
      window.contentMinSize = NSSize(width: 660, height: 560)
      window.setContentSize(NSSize(width: 660, height: 560))
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.center()
      onboardingWindowController = NSWindowController(window: window)
    } else if let window = onboardingWindowController?.window,
      window.contentLayoutRect.width < 660 || window.contentLayoutRect.height < 560
    {
      window.contentMinSize = NSSize(width: 660, height: 560)
      window.setContentSize(NSSize(width: 660, height: 560))
      window.center()
    }
    onboardingWindowController?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
  }

  func closeOnboarding() {
    onboardingWindowController?.close()
  }

  func windowWillClose(_ notification: Notification) {
    if notification.object as? NSWindow === onboardingWindowController?.window,
      model.isOnboardingPresented
    {
      model.finishOnboarding()
    }
  }

  func showGestureHelp() {
    if helpWindowController == nil {
      let styleMask: NSWindow.StyleMask =
        if #available(macOS 26.0, *) {
          [.titled, .closable, .resizable, .fullSizeContentView]
        } else {
          [.titled, .closable, .resizable]
        }
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 610, height: 660),
        styleMask: styleMask, backing: .buffered, defer: false
      )
      window.title = String(localized: "Gesture Help")
      if #available(macOS 26.0, *) {
        window.toolbarStyle = .unified
      }
      window.contentViewController = NSHostingController(
        rootView: GestureHelpView(
          model: model, showSettings: { [weak self] in self?.showSettings() }
        )
        .preferredColorScheme(model.interfaceAppearance.preferredColorScheme)
      )
      window.isReleasedWhenClosed = false
      window.contentMinSize = NSSize(width: 530, height: 430)
      window.setFrameAutosaveName("iGestures.GestureHelpWindow")
      window.center()
      helpWindowController = NSWindowController(window: window)
    }
    helpWindowController?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    helpWindowController?.window?.makeKeyAndOrderFront(nil)
  }

  func showSettings() {
    let windowController =
      windowController ?? makeWindowController()
    self.windowController = windowController
    windowController.showWindow(nil)
    windowController.window?.makeKeyAndOrderFront(nil)

    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      windowController.window?.makeKeyAndOrderFront(nil)
    }
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
        .fullSizeContentView,
      ],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    #if DEBUG
      window.title = "iGestures Debug"
    #else
      window.title = "iGestures"
    #endif
    if #available(macOS 26.0, *) {
      window.toolbarStyle = .unified
    } else {
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.titlebarSeparatorStyle = .none
      window.isMovableByWindowBackground = true
    }
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

@MainActor
private func isGestureRecognitionActive(_ model: AppModel) -> Bool {
  model.isEnabled
    && !model.isPracticingGesture
    && model.permissionState == .granted
    && model.eventTapState == .running
}

@MainActor
private func gestureRecognitionStatus(_ model: AppModel) -> String {
  if model.isPracticingGesture {
    return String(localized: "Live gestures are paused while practicing.")
  }
  guard model.isEnabled else {
    return String(localized: "Gesture recognition is disabled.")
  }
  if model.permissionState == .tapCreationFailed {
    return String(localized: "Gesture recognition is unavailable.")
  }
  guard model.permissionState == .granted else {
    return String(localized: "Gesture recognition needs permission.")
  }
  switch model.eventTapState {
  case .running:
    return String(localized: "Gesture recognition is enabled.")
  case .starting:
    return String(localized: "Gesture recognition is starting.")
  case .stopped, .failedToCreateTap:
    return String(localized: "Gesture recognition is unavailable.")
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

@MainActor
final class IGesturesIntentBridge {
  static let shared = IGesturesIntentBridge()

  private weak var model: AppModel?

  private init() {}

  func install(_ model: AppModel) {
    self.model = model
  }

  func setRecognitionEnabled(_ enabled: Bool) -> Bool {
    guard let model else { return false }
    model.setRecognitionEnabled(enabled)
    return model.isEnabled == enabled
  }

  func activateConfigurationSet(named name: String) -> Bool {
    model?.activateGestureConfigurationSet(named: name) == true
  }

  func runNamedAction(named name: String) -> Bool {
    model?.runSafeNamedGestureAction(named: name) == true
  }
}

private enum IGesturesIntentError: LocalizedError {
  case appUnavailable
  case configurationSetNotFound
  case namedActionNotAllowed

  var errorDescription: String? {
    switch self {
    case .appUnavailable:
      String(localized: "iGestures is not ready.")
    case .configurationSetNotFound:
      String(localized: "The configuration set was not found.")
    case .namedActionNotAllowed:
      String(
        localized:
          "The named action was not found or is not allowed for App Intents."
      )
    }
  }
}

struct SetGestureRecognitionIntent: AppIntent {
  static let title: LocalizedStringResource =
    "Set Gesture Recognition"
  static let description = IntentDescription(
    "Enable or disable iGestures recognition."
  )

  @Parameter(title: "Enabled")
  var enabled: Bool

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard IGesturesIntentBridge.shared.setRecognitionEnabled(enabled)
    else {
      throw IGesturesIntentError.appUnavailable
    }
    return .result(
      dialog:
        enabled
        ? "Gesture recognition is enabled."
        : "Gesture recognition is disabled."
    )
  }
}

struct SwitchGestureConfigurationSetIntent: AppIntent {
  static let title: LocalizedStringResource =
    "Switch Gesture Configuration"
  static let description = IntentDescription(
    "Activate one named iGestures configuration set."
  )

  @Parameter(title: "Configuration Set")
  var configurationSetName: String

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard
      IGesturesIntentBridge.shared.activateConfigurationSet(
        named: configurationSetName
      )
    else {
      throw IGesturesIntentError.configurationSetNotFound
    }
    return .result(dialog: "Gesture configuration switched.")
  }
}

struct RunSafeNamedGestureActionIntent: AppIntent {
  static let title: LocalizedStringResource = "Run Named Gesture Action"
  static let description = IntentDescription(
    "Run an iGestures named action that was explicitly allowed for App Intents."
  )

  @Parameter(title: "Named Action")
  var actionName: String

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard IGesturesIntentBridge.shared.runNamedAction(named: actionName)
    else {
      throw IGesturesIntentError.namedActionNotAllowed
    }
    return .result(dialog: "Named gesture action started.")
  }
}

struct IGesturesAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SetGestureRecognitionIntent(),
      phrases: ["Set gesture recognition in \(.applicationName)"],
      shortTitle: "Gesture Recognition",
      systemImageName: "hand.draw"
    )
    AppShortcut(
      intent: SwitchGestureConfigurationSetIntent(),
      phrases: ["Switch gesture configuration in \(.applicationName)"],
      shortTitle: "Switch Configuration",
      systemImageName: "square.stack.3d.up"
    )
    AppShortcut(
      intent: RunSafeNamedGestureActionIntent(),
      phrases: ["Run a named gesture action in \(.applicationName)"],
      shortTitle: "Run Named Action",
      systemImageName: "bolt.shield"
    )
  }
}

private struct OnboardingView: View {
  @ObservedObject var model: AppModel

  @State private var step = 0
  @State private var selectedPresetIDs = Set(
    GesturePresetLibrary.builtIn.prefix(3).map(\.id)
  )
  @State private var practiceSucceeded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text(String(localized: "Welcome to iGestures"))
          .font(.largeTitle)
          .fontWeight(.bold)
        Spacer()
        if LiquidGlassStyle.isAvailable {
          HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
              Capsule()
                .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.28))
                .frame(width: index == step ? 22 : 8, height: 6)
                .animation(.easeInOut(duration: 0.2), value: step)
            }
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            String(
              format: String(localized: "Step %d of %d"),
              step + 1,
              4
            )
          )
        } else {
          Text(
            String(
              format: String(localized: "Step %d of %d"),
              step + 1,
              4
            )
          )
          .foregroundStyle(.secondary)
        }
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

      if !LiquidGlassStyle.isAvailable {
        Divider()
      }

      HStack {
        Button(String(localized: "Skip Setup")) {
          complete()
        }
        .adaptiveGlassButtonStyle()
        Spacer()
        if step > 0 {
          Button(String(localized: "Back")) {
            step -= 1
          }
          .adaptiveGlassButtonStyle()
        }
        if step < 3 {
          Button(String(localized: "Continue")) {
            step += 1
          }
          .adaptiveGlassButtonStyle(prominent: true)
          .keyboardShortcut(.defaultAction)
          .disabled(step == 2 && selectedPresetIDs.isEmpty)
        } else {
          Button(String(localized: "Finish")) {
            model.installPresets(selectedPresets)
            complete()
          }
          .adaptiveGlassButtonStyle(prominent: true)
          .keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(28)
    .frame(
      minWidth: 660,
      idealWidth: 660,
      maxWidth: .infinity,
      minHeight: 560,
      idealHeight: 560,
      maxHeight: .infinity
    )
    .onAppear {
      step = 0
    }
    .onChange(of: model.isOnboardingPresented) {
      if model.isOnboardingPresented {
        step = 0
      }
    }
    .onChange(of: selectedPresetIDs) {
      practiceSucceeded = false
    }
  }

  private var permissionStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(
        String(localized: "Required Permissions"),
        systemImage: "hand.raised.fill"
      )
      .font(.title2)
      .accessibilityAddTraits(.isHeader)

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

      Group {
        VStack(alignment: .leading, spacing: 8) {
          onboardingPermissionRow(
            String(localized: "Read Mouse Input"),
            isGranted: model.permissionDiagnostics.listenEventAccess
          )
          onboardingPermissionRow(
            String(localized: "Send Shortcuts and Clicks"),
            isGranted: model.permissionDiagnostics.postEventAccess
          )
          onboardingPermissionRow(
            String(localized: "Accessibility Control"),
            isGranted: model.permissionDiagnostics.accessibilityTrusted
          )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .modifier(OnboardingChecklistCardModifier())
    }
  }

  private var triggerStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(
        String(localized: "Choose a Trigger Button"),
        systemImage: "computermouse"
      )
      .font(.title2)
      .accessibilityAddTraits(.isHeader)

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

      TriggerButtonRecorderView(model: model) {
        model.setTriggerButton($0)
      }
    }
  }

  private var presetStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(
        String(localized: "Choose Starter Gestures"),
        systemImage: "square.grid.2x2"
      )
      .font(.title2)
      .accessibilityAddTraits(.isHeader)

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
              .accessibilityHidden(true)
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

      if selectedPresetIDs.isEmpty {
        Label(
          String(
            localized:
              "Select at least one starter gesture to continue."
          ),
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
    }
  }

  private var practiceStep: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(
        String(localized: "Practice"),
        systemImage: "checkmark.circle"
      )
      .font(.title2)
      .accessibilityAddTraits(.isHeader)

      Text(
        String(
          localized:
            "Practice is optional. You can finish setup now or try the gesture first."
        )
      )
      .foregroundStyle(.secondary)

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
          .accessibilityHidden(true)
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
  }

  private func onboardingTriggerLabel(
    _ button: GestureTriggerButton
  ) -> String {
    button.localizedName
  }

  private func onboardingPermissionRow(
    _ title: String,
    isGranted: Bool
  ) -> some View {
    Label(
      title,
      systemImage:
        isGranted
        ? "checkmark.circle.fill"
        : "exclamationmark.circle.fill"
    )
    .foregroundStyle(isGranted ? .green : .orange)
  }
}

struct GesturePracticePad: View {
  let template: GestureTemplate
  @Binding var succeeded: Bool
  @State private var points: [GesturePoint] = []
  @State private var message = String(
    localized: "Draw here without executing an action."
  )
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    let useLuminous = LiquidGlassStyle.isAvailable && !reduceTransparency
    let cornerRadius: CGFloat = LiquidGlassStyle.isAvailable ? 16 : 10
    Canvas { context, size in
      let bounds = Path(
        roundedRect: CGRect(origin: .zero, size: size),
        cornerRadius: cornerRadius,
        style: .continuous
      )
      context.fill(
        bounds,
        with: .color(
          LiquidGlassStyle.isAvailable
            ? Color.primary.opacity(0.04)
            : Color.secondary.opacity(0.08)
        )
      )
      if LiquidGlassStyle.isAvailable {
        context.stroke(
          bounds,
          with: .color(Color.primary.opacity(0.1)),
          lineWidth: 1
        )
      }
      guard let first = points.first else { return }
      let strokeColor: Color = succeeded ? .green : .accentColor
      if useLuminous {
        let cgPoints = points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        LuminousCanvasTrail.draw(
          in: &context,
          points: cgPoints,
          color: strokeColor,
          maxRadius: 2.5,
          glowBlurRadius: 5.5,
          showsMarkers: false,
          showsLiveHead: !succeeded
        )
        return
      }
      var path = Path()
      path.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
      for point in points.dropFirst() {
        path.addLine(
          to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
        )
      }
      context.stroke(
        path,
        with: .color(strokeColor),
        style: StrokeStyle(
          lineWidth: 4,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "Gesture practice area"))
    .accessibilityHint(
      String(localized: "Draw the previewed gesture in this area.")
    )
    .accessibilityValue(message)
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
      if LiquidGlassStyle.isAvailable {
        Text(message)
          .font(.callout)
          .foregroundStyle(succeeded ? .green : .secondary)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .adaptiveGlassCapsule(tint: succeeded ? .green.opacity(0.15) : nil)
          .padding(10)
      } else {
        Text(message)
          .font(.callout)
          .padding(8)
      }
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

private struct OnboardingChecklistCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    if LiquidGlassStyle.isAvailable {
      content
        .padding(14)
        .adaptiveGlassCard(cornerRadius: 14)
    } else {
      content
    }
  }
}

#if !UI_PREVIEW
  @MainActor
  private final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let showSettings: () -> Void
    private let showGestureHelp: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(
      withLength: NSStatusItem.variableLength
    )
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []

    init(
      model: AppModel,
      showSettings: @escaping () -> Void,
      showGestureHelp: @escaping () -> Void
    ) {
      self.model = model
      self.showSettings = showSettings
      self.showGestureHelp = showGestureHelp
      super.init()

      menu.autoenablesItems = false
      menu.delegate = self
      statusItem.menu = menu
      statusItem.isVisible = true

      configureButton()
      observeState()
      updateButton()
    }

    func ensureVisible() {
      statusItem.isVisible = true
      updateButton()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
      menu.removeAllItems()
      applyAppearance(to: menu)

      let statusItemHeader = NSMenuItem(
        title: gestureRecognitionStatus(model),
        action: nil,
        keyEquivalent: ""
      )
      statusItemHeader.isEnabled = false
      menu.addItem(statusItemHeader)

      menu.addItem(.separator())

      menu.addItem(
        makeActionItem(
          title: model.isEnabled
            ? String(localized: "Disable")
            : String(localized: "Enable"),
          systemImage: model.isEnabled ? "pause.circle" : "play.circle"
        ) { [model] in
          model.toggleEnabled()
        }
      )

      if let applicationName = model.currentApplicationName {
        menu.addItem(
          makeActionItem(
            title: model.isCurrentApplicationExcluded
              ? String(
                format: String(localized: "Enable in %@"),
                applicationName
              )
              : String(
                format: String(localized: "Exclude %@"),
                applicationName
              ),
            systemImage: model.isCurrentApplicationExcluded
              ? "checkmark.circle"
              : "nosign"
          ) { [model] in
            model.setCurrentApplicationExcluded(
              !model.isCurrentApplicationExcluded
            )
          }
        )

        let triggerSubmenuItem = NSMenuItem(
          title: String(localized: "Exclude Current App for Trigger"),
          action: nil,
          keyEquivalent: ""
        )
        if LiquidGlassStyle.isAvailable {
          triggerSubmenuItem.image = NSImage(
            systemSymbolName: "computermouse",
            accessibilityDescription: nil
          )
        }
        let triggerSubmenu = NSMenu()
        triggerSubmenu.autoenablesItems = false
        for button in GestureTriggerButton.commonPresets {
          triggerSubmenu.addItem(
            makeActionItem(title: button.localizedName) { [model] in
              model.setCurrentApplicationExcluded(
                true,
                triggerButton: button
              )
            }
          )
        }
        triggerSubmenuItem.submenu = triggerSubmenu
        menu.addItem(triggerSubmenuItem)
      }

      menu.addItem(.separator())

      let permissionHeader = NSMenuItem(
        title: model.permissionStatusText,
        action: nil,
        keyEquivalent: ""
      )
      permissionHeader.isEnabled = false
      menu.addItem(permissionHeader)

      menu.addItem(
        makeActionItem(
          title: String(localized: "Current App Gestures…"),
          systemImage: "hand.draw"
        ) { [model, showGestureHelp] in
          model.gestureHelpPage = .reference
          showGestureHelp()
        }
      )

      menu.addItem(
        makeActionItem(
          title: String(localized: "Diagnose Last Gesture…"),
          systemImage: "stethoscope"
        ) { [model, showGestureHelp] in
          model.gestureHelpPage = .diagnostics
          showGestureHelp()
        }
      )

      if model.permissionState != .granted
        || model.eventTapState == .failedToCreateTap
      {
        menu.addItem(
          makeActionItem(
            title: String(localized: "Review Permissions…"),
            systemImage: "exclamationmark.shield"
          ) { [model, showSettings] in
            model.requestPermissionsSettings()
            showSettings()
          }
        )
      }

      menu.addItem(
        makeActionItem(
          title: String(localized: "Settings…"),
          systemImage: "gearshape",
          keyEquivalent: ","
        ) { [showSettings] in
          showSettings()
        }
      )

      menu.addItem(.separator())

      menu.addItem(
        makeActionItem(
          title: String(localized: "Quit"),
          systemImage: "power",
          keyEquivalent: "q"
        ) { [model] in
          model.terminate()
        }
      )
    }

    private func configureButton() {
      guard let button = statusItem.button else { return }
      button.image = MenuBarTemplateImage.icon
      #if DEBUG
        button.imagePosition = .imageLeading
        button.title = "DEV"
        button.font = .monospacedSystemFont(ofSize: 9.5, weight: .bold)
        button.setAccessibilityLabel("iGestures Debug")
      #else
        button.imagePosition = .imageOnly
        button.title = ""
        button.setAccessibilityLabel("iGestures")
      #endif
    }

    private func observeState() {
      Publishers.Merge4(
        model.$isEnabled.map { _ in () },
        model.$isPracticingGesture.map { _ in () },
        model.$permissionState.map { _ in () },
        model.$eventTapState.map { _ in () }
      )
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateButton()
      }
      .store(in: &cancellables)
    }

    private func updateButton() {
      statusItem.isVisible = true
      guard let button = statusItem.button else { return }
      let status = gestureRecognitionStatus(model)
      button.appearsDisabled = !isGestureRecognitionActive(model)
      #if DEBUG
        button.toolTip = "iGestures Debug — \(status)"
      #else
        button.toolTip = status
      #endif
      button.setAccessibilityValue(status)
    }

    private func applyAppearance(to menu: NSMenu) {
      switch model.interfaceAppearance {
      case .system:
        menu.appearance = nil
      case .light:
        menu.appearance = NSAppearance(named: .aqua)
      case .dark:
        menu.appearance = NSAppearance(named: .darkAqua)
      }
    }

    private func makeActionItem(
      title: String,
      systemImage: String? = nil,
      keyEquivalent: String = "",
      handler: @escaping () -> Void
    ) -> NSMenuItem {
      let target = MenuActionTarget(handler)
      let item = NSMenuItem(
        title: title,
        action: #selector(MenuActionTarget.invoke(_:)),
        keyEquivalent: keyEquivalent
      )
      item.target = target
      item.representedObject = target
      if LiquidGlassStyle.isAvailable, let systemImage {
        item.image = NSImage(
          systemSymbolName: systemImage,
          accessibilityDescription: nil
        )
      }
      return item
    }
  }

  @MainActor
  private final class MenuActionTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
      self.handler = handler
    }

    @objc func invoke(_ sender: Any?) {
      handler()
    }
  }
#endif
