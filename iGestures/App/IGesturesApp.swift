import AppKit
import SwiftUI

@main
struct IGesturesApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    MenuBarExtra {
      MenuBarContent(model: model)
    } label: {
      Label {
        Text("iGestures")
      } icon: {
        Image(
          systemName: model.isEnabled
            ? "cursorarrow.motionlines"
            : "cursorarrow.slash")
      }
    }

    Settings {
      SettingsRootView(model: model)
    }
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
}
