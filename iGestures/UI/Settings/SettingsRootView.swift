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
    .frame(width: 760, height: 520)
  }
}

private struct GeneralSettingsView: View {
  @ObservedObject var model: AppModel

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

      LabeledContent(String(localized: "Trigger Mouse Button")) {
        HStack {
          Picker(
            "",
            selection: Binding(
              get: { model.triggerButton },
              set: { model.setTriggerButton($0) }
            )
          ) {
            ForEach(GestureTriggerButton.commonPresets) { button in
              Text(triggerButtonLabel(button)).tag(button)
            }
            if !GestureTriggerButton.commonPresets.contains(
              model.triggerButton
            ) {
              Text(triggerButtonLabel(model.triggerButton))
                .tag(model.triggerButton)
            }
          }
          .labelsHidden()
          .frame(width: 170)

          TriggerButtonRecorderView(model: model)
        }
      }

      LabeledContent(
        String(localized: "Trigger Hold Duration")
      ) {
        Stepper(
          value: Binding(
            get: { model.triggerDuration },
            set: { model.setTriggerDuration($0) }
          ),
          in: triggerDurationRange,
          step: 0.05
        ) {
          Text(
            triggerDurationLabel(model.triggerDuration)
          )
          .monospacedDigit()
        }
      }
      Text(
        String(
          localized:
            "Gesture tracking starts when either this hold duration or the movement threshold is reached."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)

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

      LabeledContent(String(localized: "Configuration")) {
        HStack {
          Button(String(localized: "Import…")) {
            chooseImportFile()
          }
          Button(String(localized: "Export…")) {
            chooseExportFile()
          }
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
    model.importMappings(from: url)
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
    switch button.buttonNumber {
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

  private func triggerDurationLabel(_ duration: TimeInterval) -> String {
    guard duration > 0 else {
      return String(localized: "No Delay")
    }
    return String(
      format: String(localized: "%.2f seconds"),
      duration
    )
  }

  private var triggerDurationRange: ClosedRange<TimeInterval> {
    let minimum = GestureInputConfiguration.minimumTriggerDuration
    let maximum = GestureInputConfiguration.maximumTriggerDuration
    return minimum...maximum
  }
}

private struct TriggerButtonRecorderView: View {
  @ObservedObject var model: AppModel
  @State private var recordingID: UUID?

  var body: some View {
    Button(
      recordingID == nil
        ? String(localized: "Record…")
        : String(localized: "Press a Mouse Button…")
    ) {
      beginRecording()
    }
    .disabled(
      recordingID == nil && model.eventTapState != .running
    )
    .onDisappear {
      cancelRecording()
    }
  }

  private func beginRecording() {
    guard recordingID == nil else { return }
    recordingID = model.beginTriggerButtonRecording { button in
      Task { @MainActor in
        model.setTriggerButton(button)
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

      LabeledContent(String(localized: "Accessibility")) {
        diagnosticLabel(
          isGranted:
            model.permissionDiagnostics.accessibilityTrusted
        )
      }

      LabeledContent(String(localized: "Listen Event Access")) {
        diagnosticLabel(
          isGranted:
            model.permissionDiagnostics.listenEventAccess
        )
      }

      LabeledContent(String(localized: "Post Event Access")) {
        diagnosticLabel(
          isGranted:
            model.permissionDiagnostics.postEventAccess
        )
      }

      LabeledContent(String(localized: "Event Tap")) {
        Text(eventTapStatus)
      }

      if model.canRequestAccess {
        Button(String(localized: "Grant Access")) {
          model.requestAccess()
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
}
