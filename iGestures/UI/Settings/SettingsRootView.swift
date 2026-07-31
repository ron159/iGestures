import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSidebarMetrics {
  static let width: CGFloat = 232
  static let minimumWorkspaceWidth: CGFloat = 664
}

struct SettingsRootView: View {
  static let minimumContentSize = NSSize(width: 900, height: 600)

  let model: AppModel

  var body: some View {
    GesturesSettingsView(model: model)
      .frame(
        minWidth: Self.minimumContentSize.width,
        idealWidth: 1_100,
        maxWidth: .infinity,
        minHeight: Self.minimumContentSize.height,
        idealHeight: 700,
        maxHeight: .infinity
      )
      .background(
        WindowMinimumSizeConfigurator(
          minimumSize: Self.minimumContentSize
        )
      )
  }
}

private struct WindowMinimumSizeConfigurator: NSViewRepresentable {
  let minimumSize: NSSize

  func makeNSView(context: Context) -> WindowMinimumSizeView {
    WindowMinimumSizeView(minimumSize: minimumSize)
  }

  func updateNSView(
    _ nsView: WindowMinimumSizeView,
    context: Context
  ) {
    nsView.minimumSize = minimumSize
  }
}

private final class WindowMinimumSizeView: NSView {
  var minimumSize: NSSize {
    didSet {
      configureWindow()
    }
  }

  init(minimumSize: NSSize) {
    self.minimumSize = minimumSize
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    configureWindow()
  }

  private func configureWindow() {
    guard let window else { return }
    window.contentMinSize = minimumSize

    let contentSize = window.contentLayoutRect.size
    guard
      contentSize.width < minimumSize.width
        || contentSize.height < minimumSize.height
    else {
      return
    }

    window.setContentSize(
      NSSize(
        width: max(contentSize.width, minimumSize.width),
        height: max(contentSize.height, minimumSize.height)
      )
    )
  }
}

struct GeneralSettingsView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var model: AppModel
  @State private var isPracticePresented = false

  var body: some View {
    Form {
      Section(String(localized: "General")) {
        Toggle(
          String(localized: "Enable gesture recognition"),
          isOn: Binding(
            get: { model.isEnabled },
            set: { _ in model.toggleEnabled() }
          )
        )

        Toggle(
          String(localized: "Show Gesture Trail"),
          isOn: Binding(
            get: { model.isOverlayEnabled },
            set: { model.setOverlayEnabled($0) }
          )
        )

        ColorPicker(
          String(localized: "Gesture Trail Color"),
          selection: Binding(
            get: { Color(nsColor: model.trailColor) },
            set: { model.setTrailColor(NSColor($0)) }
          ),
          supportsOpacity: false
        )
        .disabled(!model.isOverlayEnabled)

        Toggle(
          String(localized: "Show Recognition Feedback"),
          isOn: Binding(
            get: { model.isFeedbackEnabled },
            set: { model.setFeedbackEnabled($0) }
          )
        )

        Picker(
          String(localized: "Recognition Sensitivity"),
          selection: Binding(
            get: { model.recognitionSensitivity },
            set: { model.setRecognitionSensitivity($0) }
          )
        ) {
          Text(String(localized: "Loose"))
            .tag(RecognitionSensitivity.loose)
          Text(String(localized: "Standard"))
            .tag(RecognitionSensitivity.standard)
          Text(String(localized: "Strict"))
            .tag(RecognitionSensitivity.strict)
        }

        LabeledContent(String(localized: "Global Enable Shortcut")) {
          ShortcutRecorderView(
            shortcut: Binding(
              get: { model.globalToggleShortcut },
              set: { model.setGlobalToggleShortcut($0) }
            ),
            model: model
          )
          .frame(width: 170)
        }

        if let conflict = SystemShortcutConflictDetector().conflict(
          for: model.globalToggleShortcut
        ) {
          Text(conflict.localizedDescription)
            .foregroundStyle(.orange)
        }
      }

      Section(String(localized: "Gesture Trigger")) {
        Text(
          String(
            localized:
              "Hold the primary trigger to draw. Add a secondary trigger for higher-priority actions."
          )
        )
        .foregroundStyle(.secondary)

        LabeledContent(String(localized: "Primary Trigger")) {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
              primaryTriggerPicker
              primaryTriggerRecorder
            }
            VStack(alignment: .trailing, spacing: 8) {
              primaryTriggerPicker
              primaryTriggerRecorder
            }
          }
        }

        LabeledContent(String(localized: "Secondary Trigger")) {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
              secondaryTriggerPicker
              secondaryTriggerRecorder
            }
            VStack(alignment: .trailing, spacing: 8) {
              secondaryTriggerPicker
              secondaryTriggerRecorder
            }
          }
        }

        LabeledContent(String(localized: "Trigger Hold Duration")) {
          triggerDurationStepper
        }

        if let error = model.triggerConfigurationError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }

      Section(String(localized: "System")) {
        Toggle(
          String(localized: "Enable Trackpad Modifier Gestures"),
          isOn: Binding(
            get: { model.isTrackpadGestureEnabled },
            set: { model.setTrackpadGestureEnabled($0) }
          )
        )

        if model.isTrackpadGestureEnabled {
          Picker(
            String(localized: "Trackpad Modifiers"),
            selection: Binding(
              get: { model.trackpadModifiers },
              set: { model.setTrackpadModifiers($0) }
            )
          ) {
            Text(String(localized: "Control + Option"))
              .tag(UInt64(0x4_0000 | 0x8_0000))
            Text(String(localized: "Command + Option"))
              .tag(UInt64(0x10_0000 | 0x8_0000))
            Text(String(localized: "Control + Command"))
              .tag(UInt64(0x4_0000 | 0x10_0000))
          }
        }

        Toggle(
          String(localized: "Haptic Feedback"),
          isOn: Binding(
            get: { model.isHapticFeedbackEnabled },
            set: { model.setHapticFeedbackEnabled($0) }
          )
        )

        Toggle(
          String(localized: "Launch at Login"),
          isOn: Binding(
            get: { model.isLaunchAtLoginEnabled },
            set: { model.setLaunchAtLoginEnabled($0) }
          )
        )
        .disabled(!model.canChangeLaunchAtLogin)

        if model.loginItemState == .requiresApproval {
          LabeledContent(String(localized: "Launch at Login")) {
            Button(String(localized: "Open System Settings")) {
              model.openLoginItemSettings()
            }
          }
          Text(
            String(
              localized:
                "Launch at login requires approval in System Settings."
            )
          )
          .foregroundStyle(.secondary)
        } else if model.loginItemState == .notFound {
          Text(
            String(
              localized:
                "Launch at login is unavailable in this build."
            )
          )
          .foregroundStyle(.secondary)
        }

        if let error = model.loginItemError {
          Text(error)
            .foregroundStyle(.red)
        }
      }

      Section(String(localized: "Getting Started")) {
        adaptiveControlGroup {
          Button(String(localized: "Practice Gestures")) {
            isPracticePresented = true
          }
          Button(String(localized: "Open Setup Guide")) {
            model.reopenOnboarding()
            openWindow(id: "onboarding")
          }
        }
      }

    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      model.refreshLoginItemStatus()
    }
    .sheet(isPresented: $isPracticePresented) {
      GesturePracticeSettingsSheet()
    }
  }

  private var primaryTriggerPicker: some View {
    Picker(
      String(localized: "Primary Trigger"),
      selection: Binding(
        get: { model.triggerButton },
        set: { model.setTriggerButton($0) }
      )
    ) {
      ForEach(GestureTriggerButton.commonPresets) { button in
        Text(button.localizedName).tag(button)
      }
      if !GestureTriggerButton.commonPresets.contains(
        model.triggerButton
      ) {
        Text(model.triggerButton.localizedName)
          .tag(model.triggerButton)
      }
    }
    .labelsHidden()
    .frame(width: 165)
  }

  private var primaryTriggerRecorder: some View {
    TriggerButtonRecorderView(model: model) {
      model.setTriggerButton($0)
    }
    .frame(width: 170, alignment: .trailing)
  }

  private var secondaryTriggerPicker: some View {
    Picker(
      String(localized: "Secondary Trigger"),
      selection: Binding(
        get: { model.secondaryTriggerButton },
        set: { model.setSecondaryTriggerButton($0) }
      )
    ) {
      Text(String(localized: "Disabled"))
        .tag(GestureTriggerButton?.none)
      ForEach(availableSecondaryTriggerButtons) { button in
        Text(button.localizedName)
          .tag(GestureTriggerButton?.some(button))
      }
    }
    .labelsHidden()
    .frame(width: 165)
  }

  private var secondaryTriggerRecorder: some View {
    TriggerButtonRecorderView(model: model) {
      model.setSecondaryTriggerButton($0)
    }
    .frame(width: 170, alignment: .trailing)
  }

  private var triggerDurationStepper: some View {
    Stepper(
      value: Binding(
        get: { model.triggerDuration },
        set: { model.setTriggerDuration($0) }
      ),
      in: triggerDurationRange,
      step: 0.05
    ) {
      Text(triggerDurationLabel(model.triggerDuration))
        .monospacedDigit()
    }
  }

  private var triggerDurationRange: ClosedRange<TimeInterval> {
    let minimum = GestureInputConfiguration.minimumTriggerDuration
    let maximum = GestureInputConfiguration.maximumTriggerDuration
    return minimum...maximum
  }

  private var availableSecondaryTriggerButtons: [GestureTriggerButton] {
    var buttons = GestureTriggerButton.commonPresets.filter { button in
      button != model.triggerButton
        && !model.mappings.contains {
          $0.triggerButton == button
        }
    }
    if let current = model.secondaryTriggerButton,
      !buttons.contains(current)
    {
      buttons.append(current)
    }
    return buttons
  }

  private func triggerDurationLabel(_ duration: TimeInterval) -> String {
    guard duration > 0 else {
      return String(localized: "No Delay")
    }
    return String(
      format: String(localized: "%.2f seconds"),
      duration
    )
  }

  private func adaptiveControlGroup<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        content()
      }
      VStack(alignment: .trailing, spacing: 8) {
        content()
      }
    }
  }
}

struct AboutSettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        HStack(alignment: .top, spacing: 18) {
          Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 6) {
            Text("iGestures")
              .font(.title.bold())
            Text(versionText)
              .font(.callout)
              .foregroundStyle(.secondary)
            Text(
              String(
                localized:
                  "iGestures is a native macOS mouse gesture app for turning simple gestures into shortcuts, window actions, app launches, and automations."
              )
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.vertical, 8)
      }

      Section(String(localized: "Links")) {
        aboutLink(
          title: String(localized: "Official Website"),
          detail: "igestures.techkoala.net",
          systemImage: "globe",
          destination: websiteURL
        )
        aboutLink(
          title: String(localized: "GitHub"),
          detail: "github.com/ron159/iGestures",
          systemImage: "chevron.left.forwardslash.chevron.right",
          destination: githubURL
        )
      }

      Section(String(localized: "Software Update")) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            updateButtons
          }
          VStack(alignment: .leading, spacing: 8) {
            updateButtons
          }
        }

        if let updateMessage = model.updateMessage {
          Text(updateMessage)
            .foregroundStyle(
              model.updateState == .failed
                ? Color.red
                : Color.secondary
            )
        }
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  @ViewBuilder
  private var updateButtons: some View {
    Button(String(localized: "Check for Updates")) {
      model.checkForUpdates(manual: true)
    }
    .disabled(
      model.updateState == .checking
        || isUpdateOperationInProgress
    )

    if case .available = model.updateState {
      Button(String(localized: "Skip This Version")) {
        model.skipAvailableUpdate()
      }
      if model.canInstallAvailableUpdate {
        Button(String(localized: "Install and Restart")) {
          model.installAvailableUpdate()
        }
        .buttonStyle(.borderedProminent)
      } else if model.canOpenAvailableGitHubRelease {
        Button(String(localized: "View Release")) {
          model.openAvailableGitHubRelease()
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private func aboutLink(
    title: String,
    detail: String,
    systemImage: String,
    destination: URL
  ) -> some View {
    Link(destination: destination) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .font(.title3)
          .frame(width: 26)
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .foregroundStyle(.primary)
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "arrow.up.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var versionText: String {
    let version =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "—"
    let build =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleVersion"
      ) as? String ?? "—"
    return String(
      format: String(localized: "Version %@ (%@)"),
      version,
      build
    )
  }

  private var isUpdateOperationInProgress: Bool {
    switch model.updateState {
    case .downloading, .installing:
      true
    default:
      false
    }
  }

  private var websiteURL: URL {
    URL(string: "https://igestures.techkoala.net/")!
  }

  private var githubURL: URL {
    URL(string: "https://github.com/ron159/iGestures")!
  }
}

struct AdvancedSettingsView: View {
  @ObservedObject var model: AppModel
  @ObservedObject private var diagnosticsState: GestureDiagnosticsState
  @State private var isDiagnosticsExpanded = false
  @State private var isScriptLibraryPresented = false

  init(model: AppModel) {
    _model = ObservedObject(wrappedValue: model)
    _diagnosticsState = ObservedObject(
      wrappedValue: model.diagnosticsState
    )
  }

  var body: some View {
    Form {
      Section(String(localized: "Configuration")) {
        LabeledContent(String(localized: "Stored Gestures")) {
          Text(
            String(
              format: String(localized: "%d gestures loaded"),
              model.mappingCount
            )
          )
        }

        if !model.applicationExclusions.isEmpty {
          LabeledContent(String(localized: "Excluded Applications")) {
            VStack(alignment: .trailing, spacing: 6) {
              ForEach(
                model.applicationExclusions.sorted { $0.id < $1.id }
              ) { rule in
                HStack {
                  Text(exclusionSummary(rule))
                    .font(.callout)
                  Button {
                    model.removeApplicationExclusion(rule)
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                  }
                  .buttonStyle(.borderless)
                  .help(String(localized: "Remove Application"))
                  .accessibilityLabel(
                    String(
                      format: String(localized: "Remove %@"),
                      exclusionSummary(rule)
                    )
                  )
                }
              }
            }
          }
        }

        adaptiveControlGroup {
          Button(String(localized: "Import…")) {
            chooseImportFile()
          }
          Button(String(localized: "Export…")) {
            chooseExportFile()
          }
          Button(String(localized: "Undo Import")) {
            model.undoLastImport()
          }
          .disabled(!model.canUndoLastImport)
        }
        .disabled(model.isTransferringMappings)

        if model.isTransferringMappings {
          ProgressView()
            .controlSize(.small)
        } else if let message = model.mappingTransferMessage {
          Text(message)
            .foregroundStyle(.secondary)
        }

        if let error = model.mappingStoreError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }

      Section(String(localized: "Automation")) {
        Text(
          String(
            localized:
              "Manage reusable scripts for gesture actions in one place."
          )
        )
        .foregroundStyle(.secondary)

        Button {
          isScriptLibraryPresented = true
        } label: {
          Label(
            String(localized: "Manage Scripts…"),
            systemImage: "books.vertical"
          )
        }
      }

      Section {
        DisclosureGroup(
          isExpanded: $isDiagnosticsExpanded
        ) {
          VStack(alignment: .leading, spacing: 12) {
            LabeledContent(String(localized: "Gesture Engine")) {
              Text(eventTapStatus)
            }

            Toggle(
              String(localized: "Keep diagnostics after quitting"),
              isOn: Binding(
                get: { model.isDiagnosticPersistenceEnabled },
                set: { model.setDiagnosticPersistenceEnabled($0) }
              )
            )

            if diagnosticsState.records.isEmpty {
              Text(String(localized: "No recent gesture diagnostics."))
                .foregroundStyle(.secondary)
            } else {
              GroupBox(String(localized: "Recent Gesture Diagnostics")) {
                VStack(alignment: .leading, spacing: 6) {
                  ForEach(diagnosticsState.records.suffix(8).reversed()) {
                    record in
                    HStack {
                      Text(record.timestamp, style: .time)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                      Text(diagnosticSummary(record))
                      Spacer()
                    }
                    .accessibilityElement(children: .combine)
                  }
                  HStack {
                    Spacer()
                    Button(String(localized: "Clear Diagnostics")) {
                      model.clearDiagnostics()
                    }
                  }
                }
              }
            }
          }
          .padding(.top, 8)
        } label: {
          Label(
            String(localized: "Advanced Diagnostics"),
            systemImage: "stethoscope"
          )
        }
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      if model.eventTapState == .failedToCreateTap {
        isDiagnosticsExpanded = true
      }
    }
    .onChange(of: model.eventTapState) {
      if model.eventTapState == .failedToCreateTap {
        isDiagnosticsExpanded = true
      }
    }
    .sheet(
      isPresented: Binding(
        get: { model.pendingImportPreview != nil },
        set: {
          if !$0 {
            model.cancelPendingImport()
          }
        }
      )
    ) {
      if let preview = model.pendingImportPreview {
        MappingImportPreviewView(
          preview: preview,
          onCancel: model.cancelPendingImport,
          onMerge: {
            model.performPendingImport(mode: .merge)
          },
          onReplace: {
            model.performPendingImport(mode: .replace)
          }
        )
      }
    }
    .sheet(isPresented: $isScriptLibraryPresented) {
      ScriptLibraryView(model: model)
        .frame(
          minWidth: 620,
          idealWidth: 760,
          maxWidth: 900,
          minHeight: 480,
          idealHeight: 620,
          maxHeight: 760
        )
    }
  }

  private var eventTapStatus: String {
    switch model.eventTapState {
    case .stopped:
      String(localized: "Stopped")
    case .starting:
      String(localized: "Starting")
    case .running:
      String(localized: "Running")
    case .failedToCreateTap:
      String(localized: "Unavailable")
    }
  }

  private func chooseImportFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message = String(
      localized: "Choose an iGestures JSON configuration to import."
    )
    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }
    model.prepareMappingImport(from: url)
  }

  private func chooseExportFile() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "iGestures-gestures.json"
    panel.message = String(
      localized: "Choose where to export the gesture configuration."
    )
    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }
    model.exportMappings(to: url)
  }

  private func exclusionSummary(
    _ rule: ApplicationExclusionRule
  ) -> String {
    let applicationName =
      ApplicationMetadataCache.shared.metadata(
        for: rule.bundleIdentifier
      )?.displayName
      ?? rule.bundleIdentifier
    guard let triggerButton = rule.triggerButton else {
      return applicationName
    }
    return "\(applicationName) · \(triggerButton.localizedName)"
  }

  private func diagnosticSummary(
    _ record: GestureDiagnosticRecord
  ) -> String {
    switch record.outcome {
    case .executed:
      return String(
        format: String(localized: "Executed: %@"),
        record.mappingName ?? String(localized: "Unnamed Gesture")
      )
    case .noMatch:
      return String(localized: "Gesture was not recognized")
    case .ambiguous:
      return String(localized: "Gesture result was ambiguous")
    case .actionFailed:
      return String(
        format: String(localized: "Action failed: %@"),
        record.mappingName ?? String(localized: "Unnamed Gesture")
      )
    case .cancelled:
      return String(localized: "Gesture was cancelled")
    }
  }

  private func adaptiveControlGroup<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        content()
      }
      VStack(alignment: .trailing, spacing: 8) {
        content()
      }
    }
  }
}

private struct GesturePracticeSettingsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var presetID = GesturePresetLibrary.builtIn[0].id
  @State private var succeeded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "Practice Gestures"))
        .font(.title2)
        .fontWeight(.semibold)
      Text(
        String(
          localized:
            "Practice recognition without running the configured action."
        )
      )
      .foregroundStyle(.secondary)
      Picker(String(localized: "Gesture"), selection: $presetID) {
        ForEach(GesturePresetLibrary.builtIn) { preset in
          Text(preset.name).tag(preset.id)
        }
      }
      HStack(spacing: 18) {
        GestureTemplatePreview(template: preset.template)
          .frame(width: 120, height: 120)
          .accessibilityHidden(true)
        GesturePracticePad(
          template: preset.template,
          succeeded: $succeeded
        )
        .frame(width: 340, height: 260)
      }
      Text(
        succeeded
          ? String(localized: "Practice passed.")
          : String(localized: "Draw the selected gesture to test it.")
      )
      .foregroundStyle(succeeded ? .green : .secondary)
      HStack {
        Spacer()
        Button(String(localized: "Done")) {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 540)
    .onChange(of: presetID) {
      succeeded = false
    }
  }

  private var preset: GesturePreset {
    GesturePresetLibrary.builtIn.first {
      $0.id == presetID
    } ?? GesturePresetLibrary.builtIn[0]
  }
}

private struct MappingImportPreviewView: View {
  @Environment(\.dismiss) private var dismiss
  let preview: MappingImportPreview
  let onCancel: () -> Void
  let onMerge: () -> Void
  let onReplace: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "Import Preview"))
        .font(.title2)
        .fontWeight(.semibold)

      Grid(alignment: .leading, horizontalSpacing: 20) {
        GridRow {
          Text(String(localized: "Schema"))
          Text("\(preview.schemaVersion)")
        }
        GridRow {
          Text(String(localized: "Mappings"))
          Text("\(preview.importedMappingCount)")
        }
        GridRow {
          Text(String(localized: "New Mappings"))
          Text("\(preview.mappingsToAdd)")
        }
        GridRow {
          Text(String(localized: "Action Types"))
          Text(preview.actionTypes.joined(separator: ", "))
        }
        GridRow {
          Text(String(localized: "Conflicts"))
          Text("\(preview.conflicts.count)")
            .foregroundStyle(
              preview.conflicts.isEmpty
                ? Color.secondary
                : Color.orange
            )
        }
      }

      if !preview.conflicts.isEmpty {
        Text(
          String(
            localized:
              "Merge keeps existing mappings when stable IDs collide. Similar imported gestures are added and shown for review."
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      if !preview.scriptsRequiringConfirmation.isEmpty {
        GroupBox(String(localized: "Scripts Require Review")) {
          VStack(alignment: .leading, spacing: 8) {
            Text(
              String(
                localized:
                  "Imported scripts remain disabled until you review and confirm them."
              )
            )
            .foregroundStyle(.orange)
            ForEach(
              Array(
                preview.scriptsRequiringConfirmation.enumerated()
              ),
              id: \.offset
            ) { _, script in
              Text(script.source)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(4)
                .textSelection(.enabled)
            }
          }
        }
      }

      Text(
        String(
          localized:
            "Merge is non-destructive. Replace removes the current library after creating an undo backup."
        )
      )
      .foregroundStyle(.secondary)

      HStack {
        Spacer()
        Button(String(localized: "Cancel")) {
          onCancel()
          dismiss()
        }
        Button(String(localized: "Replace All"), role: .destructive) {
          onReplace()
          dismiss()
        }
        Button(String(localized: "Merge")) {
          onMerge()
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 520)
  }
}

struct TriggerButtonRecorderView: View {
  @ObservedObject var model: AppModel
  let onRecord: (GestureTriggerButton) -> Void
  @State private var recordingID: UUID?

  var body: some View {
    Button {
      beginRecording()
    } label: {
      Label(
        recordingID == nil
          ? String(localized: "Record Trigger…")
          : String(localized: "Press a Trigger…"),
        systemImage:
          recordingID == nil ? "record.circle" : "record.circle.fill"
      )
    }
    .disabled(
      recordingID != nil || model.eventTapState != .running
    )
    .help(
      recordingID == nil
        ? String(localized: "Record a mouse button or keyboard key.")
        : String(
          localized:
            "Press a mouse button or keyboard key to use it as the trigger."
        )
    )
    .onDisappear {
      cancelRecording()
    }
  }

  private func beginRecording() {
    guard recordingID == nil else { return }
    recordingID = model.beginTriggerButtonRecording { button in
      Task { @MainActor in
        onRecord(button)
        recordingID = nil
      }
    }
  }

  private func cancelRecording() {
    guard let recordingID else { return }
    model.endTriggerButtonRecording(id: recordingID)
    self.recordingID = nil
  }
}

struct PermissionsSettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        Label(
          permissionOverview,
          systemImage:
            missingPermissionCount == 0
            ? "checkmark.shield.fill"
            : "exclamationmark.shield.fill"
        )
        .font(.headline)
        .foregroundStyle(
          missingPermissionCount == 0 ? Color.green : Color.orange
        )
      }

      Section(String(localized: "Required Permissions")) {
        permissionRow(
          title: String(localized: "Read Mouse Input"),
          description: String(
            localized: "Detects the trigger button and gesture path."
          ),
          systemImage: "computermouse",
          isGranted: model.permissionDiagnostics.listenEventAccess,
          action: model.requestListenEventAccess
        )

        permissionRow(
          title: String(localized: "Send Shortcuts and Clicks"),
          description: String(
            localized:
              "Replays normal clicks and sends configured shortcuts."
          ),
          systemImage: "keyboard",
          isGranted: model.permissionDiagnostics.postEventAccess,
          action: model.requestPostEventAccess
        )

        permissionRow(
          title: String(localized: "Accessibility Control"),
          description: String(
            localized:
              "Allows iGestures to run supported app and system actions."
          ),
          systemImage: "hand.raised",
          isGranted: model.permissionDiagnostics.accessibilityTrusted,
          action: model.requestAccessibilityAccess
        )
      }

      Section {
        LabeledContent(String(localized: "Gesture Engine")) {
          Text(eventTapStatus)
        }

        if model.eventTapState == .failedToCreateTap {
          Label(
            String(localized: "Gesture recognition is unavailable."),
            systemImage: "exclamationmark.triangle.fill"
          )
          .foregroundStyle(.orange)
        }

        Button(String(localized: "Check Again")) {
          model.refreshPermissions()
        }

        Text(
          String(
            localized:
              "Permissions are checked again when you return from System Settings."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Text(
          String(
            localized:
              "iGestures needs permission to observe mouse gestures and post the configured shortcut."
          )
        )
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      model.refreshPermissions()
    }
  }

  private var missingPermissionCount: Int {
    let diagnostics = model.permissionDiagnostics
    return [
      diagnostics.accessibilityTrusted,
      diagnostics.listenEventAccess,
      diagnostics.postEventAccess,
    ].filter { !$0 }.count
  }

  private var permissionOverview: String {
    guard missingPermissionCount > 0 else {
      return String(localized: "All required permissions are granted.")
    }
    return String(
      format: String(localized: "Permissions needing attention: %d"),
      missingPermissionCount
    )
  }

  private var eventTapStatus: String {
    switch model.eventTapState {
    case .stopped:
      String(localized: "Stopped")
    case .starting:
      String(localized: "Starting")
    case .running:
      String(localized: "Running")
    case .failedToCreateTap:
      String(localized: "Unavailable")
    }
  }

  private func diagnosticLabel(isGranted: Bool) -> some View {
    Label(
      isGranted
        ? String(localized: "Granted")
        : String(localized: "Missing"),
      systemImage: isGranted
        ? "checkmark.circle.fill"
        : "exclamationmark.triangle.fill"
    )
    .foregroundStyle(isGranted ? .green : .orange)
  }

  private func permissionRow(
    title: String,
    description: String,
    systemImage: String,
    isGranted: Bool,
    action: @escaping () -> Void
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .frame(width: 28)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .fontWeight(.medium)
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 16)

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          diagnosticLabel(isGranted: isGranted)
          if !isGranted {
            permissionButton(title: title, action: action)
          }
        }
        VStack(alignment: .trailing, spacing: 6) {
          diagnosticLabel(isGranted: isGranted)
          if !isGranted {
            permissionButton(title: title, action: action)
          }
        }
      }
    }
  }

  private func permissionButton(
    title: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(permissionActionTitle, action: action)
      .accessibilityLabel(
        String(
          format: permissionActionAccessibilityFormat,
          title
        )
      )
  }

  private var permissionActionTitle: String {
    shouldOpenSettingsForPermission
      ? String(localized: "Open System Settings")
      : String(localized: "Grant Access")
  }

  private var permissionActionAccessibilityFormat: String {
    shouldOpenSettingsForPermission
      ? String(localized: "Open settings for %@")
      : String(localized: "Grant access for %@")
  }

  private var shouldOpenSettingsForPermission: Bool {
    switch model.permissionState {
    case .checking, .denied, .tapCreationFailed:
      true
    case .unknown, .needsUserAction, .granted:
      false
    }
  }

}
