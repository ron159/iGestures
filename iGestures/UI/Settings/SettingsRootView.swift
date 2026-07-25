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
            "iGestures needs permission to observe right-button gestures and post the configured shortcut."
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
