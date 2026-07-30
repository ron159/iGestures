import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsRootView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    TabView {
      GesturesSettingsView(model: model)
        .tabItem {
          Label(
            String(localized: "Gestures"),
            systemImage: "scribble.variable"
          )
        }

      ScriptLibraryView(model: model)
        .tabItem {
          Label(
            String(localized: "Scripts"),
            systemImage: "books.vertical"
          )
        }

      GeneralSettingsView(model: model)
        .tabItem {
          Label(
            String(localized: "General"),
            systemImage: "gearshape"
          )
        }

      PermissionsSettingsView(model: model)
        .tabItem {
          Label(
            String(localized: "Permissions"),
            systemImage: "hand.raised"
          )
        }

    }
    .frame(
      minWidth: SettingsWindowConfiguration.minimumContentSize.width,
      idealWidth: 1_100,
      maxWidth: .infinity,
      minHeight: SettingsWindowConfiguration.minimumContentSize.height,
      idealHeight: 700,
      maxHeight: .infinity
    )
    .background(SettingsWindowConfigurator())
  }
}

enum SettingsWindowConfiguration {
  static let minimumContentSize = NSSize(width: 640, height: 480)

  @MainActor
  static func apply(to window: NSWindow) {
    window.styleMask.insert(.resizable)
    window.contentMinSize = minimumContentSize
    window.contentMaxSize = NSSize(width: 100_000, height: 100_000)
  }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> SettingsWindowConfigurationView {
    SettingsWindowConfigurationView()
  }

  func updateNSView(
    _ nsView: SettingsWindowConfigurationView,
    context: Context
  ) {
    nsView.configureWindow()
  }
}

private final class SettingsWindowConfigurationView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    configureWindow()
  }

  func configureWindow() {
    guard let window else { return }
    SettingsWindowConfiguration.apply(to: window)
  }
}

private struct GeneralSettingsView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var model: AppModel
  @State private var isPracticePresented = false

  var body: some View {
    Form {
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

      LabeledContent(String(localized: "Stored Gestures")) {
        Text(
          String(
            format: String(localized: "%d gestures loaded"),
            model.mappingCount
          )
        )
      }

      LabeledContent(String(localized: "Software Update")) {
        HStack {
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
      }

      if let updateMessage = model.updateMessage {
        Text(updateMessage)
          .foregroundStyle(
            model.updateState == .failed
              ? Color.red
              : Color.secondary
          )
      }

      LabeledContent(String(localized: "Getting Started")) {
        HStack {
          Button(String(localized: "Practice Gestures")) {
            isPracticePresented = true
          }
          Button(String(localized: "Open Setup Guide")) {
            model.reopenOnboarding()
            openWindow(id: "onboarding")
          }
        }
      }

      if !model.applicationExclusions.isEmpty {
        LabeledContent(String(localized: "Excluded Applications")) {
          VStack(alignment: .trailing, spacing: 6) {
            ForEach(
              model.applicationExclusions.sorted {
                $0.id < $1.id
              }
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
              }
            }
          }
        }
      }

      LabeledContent(String(localized: "Configuration")) {
        HStack {
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
        Text(error)
          .foregroundStyle(.red)
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      model.refreshLoginItemStatus()
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
    .sheet(isPresented: $isPracticePresented) {
      GesturePracticeSettingsSheet()
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

  private func triggerButtonLabel(
    _ button: GestureTriggerButton
  ) -> String {
    return switch button.buttonNumber {
    case 0:
      String(localized: "Left Mouse Button")
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

  private func exclusionSummary(
    _ rule: ApplicationExclusionRule
  ) -> String {
    let applicationName =
      NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: rule.bundleIdentifier
      )?.deletingPathExtension().lastPathComponent
      ?? rule.bundleIdentifier
    guard let triggerButton = rule.triggerButton else {
      return applicationName
    }
    return "\(applicationName) · \(triggerButtonLabel(triggerButton))"
  }

  private var isUpdateOperationInProgress: Bool {
    switch model.updateState {
    case .downloading, .installing:
      true
    default:
      false
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
          ? String(localized: "Record Button…")
          : String(localized: "Press a Mouse Button…"),
        systemImage:
          recordingID == nil ? "record.circle" : "record.circle.fill"
      )
    }
    .disabled(
      recordingID != nil || model.eventTapState != .running
    )
    .help(
      recordingID == nil
        ? String(localized: "Record a custom physical mouse button.")
        : String(
          localized:
            "Press any physical mouse button to use it as the trigger."
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

private struct PermissionsSettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      LabeledContent(String(localized: "Permission Status")) {
        Text(model.permissionStatusText)
      }

      permissionRow(
        String(localized: "Accessibility"),
        isGranted:
          model.permissionDiagnostics.accessibilityTrusted,
        action: model.requestAccessibilityAccess
      )

      permissionRow(
        String(localized: "Listen Event Access"),
        isGranted:
          model.permissionDiagnostics.listenEventAccess,
        action: model.requestListenEventAccess
      )

      permissionRow(
        String(localized: "Post Event Access"),
        isGranted:
          model.permissionDiagnostics.postEventAccess,
        action: model.requestPostEventAccess
      )

      LabeledContent(String(localized: "Event Tap")) {
        Text(eventTapStatus)
      }

      Toggle(
        String(localized: "Keep diagnostics after quitting"),
        isOn: Binding(
          get: { model.isDiagnosticPersistenceEnabled },
          set: { model.setDiagnosticPersistenceEnabled($0) }
        )
      )

      if model.recentDiagnostics.isEmpty {
        Text(String(localized: "No recent gesture diagnostics."))
          .foregroundStyle(.secondary)
      } else {
        GroupBox(String(localized: "Recent Gesture Diagnostics")) {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(model.recentDiagnostics.suffix(8).reversed()) {
              record in
              HStack {
                Text(record.timestamp, style: .time)
                  .monospacedDigit()
                  .foregroundStyle(.secondary)
                Text(diagnosticSummary(record))
                Spacer()
              }
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

      Button(String(localized: "Check Again")) {
        model.refreshPermissions()
      }

      Text(
        String(
          localized:
            "iGestures needs permission to observe mouse gestures and post the configured shortcut."
        )
      )
      .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      model.refreshPermissions()
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
    _ title: String,
    isGranted: Bool,
    action: @escaping () -> Void
  ) -> some View {
    LabeledContent(title) {
      HStack(spacing: 10) {
        diagnosticLabel(isGranted: isGranted)
        if !isGranted {
          Button(String(localized: "Grant Access"), action: action)
        }
      }
    }
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
}
