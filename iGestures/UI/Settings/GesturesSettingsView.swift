import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GesturesSettingsView: View {
  @ObservedObject var model: AppModel
  @State private var isPresentingRecorder = false
  @State private var isPresentingPresets = false
  @State private var searchText = ""
  @State private var applicationFilter = ""

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(String(localized: "Gestures"))
          .font(.title2)
          .fontWeight(.semibold)
        Spacer()
        Button {
          isPresentingPresets = true
        } label: {
          Label(
            String(localized: "Presets"),
            systemImage: "square.grid.2x2"
          )
        }
        .disabled(model.isLoadingMappings)

        Button {
          isPresentingRecorder = true
        } label: {
          Label(
            String(localized: "Add Gesture"),
            systemImage: "plus"
          )
        }
        .disabled(model.isLoadingMappings)
      }
      .padding()

      HStack {
        TextField(
          String(localized: "Search gestures"),
          text: $searchText
        )
        .textFieldStyle(.roundedBorder)

        Picker(
          String(localized: "Application"),
          selection: $applicationFilter
        ) {
          Text(String(localized: "All Applications")).tag("")
          ForEach(knownApplicationBundleIDs, id: \.self) {
            Text(applicationName(bundleIdentifier: $0)).tag($0)
          }
        }
        .frame(width: 190)

        Button(String(localized: "Enable Results")) {
          model.setMappingsEnabled(
            ids: Set(filteredMappings.map { $0.mapping.id }),
            isEnabled: true
          )
        }
        .disabled(filteredMappings.isEmpty)

        Button(String(localized: "Disable Results")) {
          model.setMappingsEnabled(
            ids: Set(filteredMappings.map { $0.mapping.id }),
            isEnabled: false
          )
        }
        .disabled(filteredMappings.isEmpty)
      }
      .padding(.horizontal)
      .padding(.bottom, 10)

      Divider()

      if model.isLoadingMappings {
        ProgressView(String(localized: "Loading Gestures…"))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.mappings.isEmpty {
        ContentUnavailableView {
          Label(
            String(localized: "No Gestures"),
            systemImage: "scribble.variable"
          )
        } description: {
          Text(
            String(
              localized:
                "Record a gesture and bind it to an action."
            )
          )
        } actions: {
          Button(String(localized: "Record Gesture")) {
            isPresentingRecorder = true
          }
        }
      } else {
        List {
          ForEach(filteredMappings, id: \.mapping.id) {
            item in
            GestureMappingRow(
              model: model,
              mapping: item.mapping,
              index: item.index,
              mappingCount: model.mappings.count
            )
          }
        }
        .listStyle(.inset)
      }

      if let error = model.mappingStoreError {
        Divider()
        Text(error)
          .font(.callout)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      }
    }
    .sheet(isPresented: $isPresentingRecorder) {
      GestureRecorderSheet(
        model: model,
        existingMappings: model.mappings
      ) { draft in
        model.createMapping(draft)
      }
    }
    .sheet(isPresented: $isPresentingPresets) {
      GesturePresetLibraryView(model: model)
    }
  }

  private var filteredMappings: [(index: Int, mapping: GestureMapping)] {
    model.mappings.enumerated().compactMap { index, mapping in
      let matchesSearch =
        searchText.isEmpty
        || mapping.name.localizedCaseInsensitiveContains(searchText)
        || (mapping.category?
          .localizedCaseInsensitiveContains(searchText) == true)
      let matchesApplication =
        applicationFilter.isEmpty
        || mapping.appScope.includes(bundleID: applicationFilter)
      return matchesSearch && matchesApplication
        ? (index, mapping)
        : nil
    }
  }

  private var knownApplicationBundleIDs: [String] {
    Array(
      Set(
        model.mappings.flatMap { mapping -> [String] in
          switch mapping.appScope {
          case .all:
            []
          case .only(let values), .allExcept(let values):
            values
          }
        })
    ).sorted()
  }

  private func applicationName(bundleIdentifier: String) -> String {
    NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: bundleIdentifier
    )?.deletingPathExtension().lastPathComponent
      ?? bundleIdentifier
  }
}

private struct GestureMappingRow: View {
  @ObservedObject var model: AppModel
  let mapping: GestureMapping
  let index: Int
  let mappingCount: Int

  @State private var name: String
  @State private var isEditingScope = false
  @State private var isEditingAction = false
  @State private var isRetraining = false
  @State private var isConfirmingDeletion = false

  init(
    model: AppModel,
    mapping: GestureMapping,
    index: Int,
    mappingCount: Int
  ) {
    self.model = model
    self.mapping = mapping
    self.index = index
    self.mappingCount = mappingCount
    _name = State(initialValue: mapping.name)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Toggle(
          "",
          isOn: Binding(
            get: { mapping.isEnabled },
            set: {
              model.setMappingEnabled(
                id: mapping.id,
                isEnabled: $0
              )
            }
          )
        )
        .labelsHidden()

        TextField(String(localized: "Gesture Name"), text: $name)
          .textFieldStyle(.plain)
          .frame(minWidth: 110)
          .onSubmit {
            commitName()
          }
          .onChange(of: mapping.name) { _, newValue in
            name = newValue
          }

        Button(actionSummary) {
          isEditingAction = true
        }
        .frame(width: 140)

        Button(scopeSummary) {
          isEditingScope = true
        }
        .frame(width: 115)

        if let conflict = shortcutConflict {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .help(conflict.localizedDescription)
        }

        Spacer()

        HStack(spacing: 4) {
          Button {
            isRetraining = true
          } label: {
            Image(systemName: "scribble.variable")
          }
          .help(String(localized: "Record Gesture Again"))

          Button {
            model.moveMapping(from: index, to: index - 1)
          } label: {
            Image(systemName: "chevron.up")
          }
          .disabled(index == 0)
          .help(String(localized: "Move Up"))

          Button {
            model.moveMapping(from: index, to: index + 1)
          } label: {
            Image(systemName: "chevron.down")
          }
          .disabled(index == mappingCount - 1)
          .help(String(localized: "Move Down"))

          Button {
            model.duplicateMapping(id: mapping.id)
          } label: {
            Image(systemName: "plus.square.on.square")
          }
          .help(String(localized: "Duplicate Gesture"))

          Button(role: .destructive) {
            isConfirmingDeletion = true
          } label: {
            Image(systemName: "trash")
          }
          .help(String(localized: "Delete Gesture"))
        }
        .buttonStyle(.borderless)
      }

      HStack(spacing: 12) {
        Text(String(localized: "Trigger"))
          .foregroundStyle(.secondary)
        Picker(
          "",
          selection: Binding(
            get: { mapping.triggerButton },
            set: {
              model.setMappingTriggerButton(
                id: mapping.id,
                triggerButton: $0
              )
            }
          )
        ) {
          Text(String(localized: "Default"))
            .tag(GestureTriggerButton?.none)
          ForEach(GestureTriggerButton.commonPresets) { button in
            Text(triggerButtonName(button))
              .tag(GestureTriggerButton?.some(button))
          }
          if let customButton = mapping.triggerButton,
            !GestureTriggerButton.commonPresets.contains(customButton)
          {
            Text(triggerButtonName(customButton))
              .tag(GestureTriggerButton?.some(customButton))
          }
        }
        .labelsHidden()
        .frame(width: 105)

        Menu(mapping.category ?? String(localized: "Uncategorized")) {
          ForEach(
            [
              String(localized: "Browser"),
              String(localized: "Navigation"),
              String(localized: "System"),
              String(localized: "Productivity"),
            ],
            id: \.self
          ) { category in
            Button(category) {
              model.setMappingCategory(
                id: mapping.id,
                category: category
              )
            }
          }
          Divider()
          Button(String(localized: "Uncategorized")) {
            model.setMappingCategory(id: mapping.id, category: nil)
          }
        }
        .frame(width: 115)

        Toggle(
          String(localized: "Repeat"),
          isOn: Binding(
            get: { mapping.repeatModeEnabled },
            set: {
              model.setMappingRepeatModeEnabled(
                id: mapping.id,
                enabled: $0
              )
            }
          )
        )
        .help(
          String(
            localized:
              "Repeat the last successful action with another trigger click."
          )
        )

        Spacer()

        Text(String(localized: "Input Device"))
          .foregroundStyle(.secondary)
        Picker(
          "",
          selection: Binding(
            get: { mapping.deviceScope },
            set: {
              model.setMappingDeviceScope(
                id: mapping.id,
                deviceScope: $0
              )
            }
          )
        ) {
          Text(String(localized: "Any Device"))
            .tag(InputDeviceScope.any)
          Text(String(localized: "Mouse"))
            .tag(InputDeviceScope.mouse(identifier: nil))
          Text(String(localized: "Trackpad"))
            .tag(InputDeviceScope.trackpad)
          if case .mouse(let identifier?) = mapping.deviceScope {
            Text(identifier)
              .tag(InputDeviceScope.mouse(identifier: identifier))
          }
        }
        .labelsHidden()
        .frame(width: 110)
      }
    }
    .padding(.vertical, 4)
    .sheet(isPresented: $isEditingScope) {
      AppScopeEditor(scope: mapping.appScope) {
        model.setMappingAppScope(id: mapping.id, appScope: $0)
      }
    }
    .sheet(isPresented: $isEditingAction) {
      GestureActionEditorSheet(
        action: mapping.action,
        model: model
      ) {
        model.setMappingAction(id: mapping.id, action: $0)
      }
    }
    .sheet(isPresented: $isRetraining) {
      GestureRecorderSheet(
        model: model,
        existingMappings: model.mappings,
        editingMapping: mapping
      ) { draft in
        model.updateMapping(id: mapping.id, with: draft)
      }
    }
    .confirmationDialog(
      String(localized: "Delete this gesture?"),
      isPresented: $isConfirmingDeletion
    ) {
      Button(String(localized: "Delete"), role: .destructive) {
        model.deleteMapping(id: mapping.id)
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    }
  }

  private var scopeSummary: String {
    switch mapping.appScope {
    case .all:
      return String(localized: "All Apps")
    case .only(let bundleIDs):
      return String(
        format: String(localized: "Only %d Apps"),
        bundleIDs.count
      )
    case .allExcept(let bundleIDs):
      return String(
        format: String(localized: "Except %d Apps"),
        bundleIDs.count
      )
    }
  }

  private var shortcutConflict: SystemShortcutConflict? {
    guard case .keyboardShortcut(let shortcut) = mapping.action else {
      return nil
    }
    return SystemShortcutConflictDetector().conflict(for: shortcut)
  }

  private var actionSummary: String {
    GestureActionSummary.text(for: mapping.action)
  }

  private func commitName() {
    let trimmedName = name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !trimmedName.isEmpty else {
      name = mapping.name
      return
    }
    name = trimmedName
    model.renameMapping(id: mapping.id, name: trimmedName)
  }

  private func triggerButtonName(
    _ button: GestureTriggerButton
  ) -> String {
    if button == .trackpad {
      return String(localized: "Trackpad")
    }
    return switch button.buttonNumber {
    case 1:
      String(localized: "Right")
    case 2:
      String(localized: "Middle")
    default:
      String(
        format: String(localized: "Button %d"),
        Int(button.buttonNumber) + 1
      )
    }
  }
}

private struct GesturePresetLibraryView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: AppModel
  @State private var selectedIDs: Set<UUID> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "Gesture Presets"))
        .font(.title2)
        .fontWeight(.semibold)

      Text(
        String(
          localized:
            "Choose presets to copy into your library. Existing gestures are never replaced."
        )
      )
      .foregroundStyle(.secondary)

      List(GesturePresetLibrary.builtIn) { preset in
        HStack(spacing: 12) {
          Toggle(
            "",
            isOn: Binding(
              get: { selectedIDs.contains(preset.id) },
              set: {
                if $0 {
                  selectedIDs.insert(preset.id)
                } else {
                  selectedIDs.remove(preset.id)
                }
              }
            )
          )
          .labelsHidden()

          GestureTemplatePreview(template: preset.template)
            .frame(width: 52, height: 42)

          VStack(alignment: .leading, spacing: 3) {
            Text(preset.name)
            Text(GestureActionSummary.text(for: preset.action))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 4)
      }
      .listStyle(.inset)

      HStack {
        Button(String(localized: "Select All")) {
          selectedIDs = Set(
            GesturePresetLibrary.builtIn.map(\.id)
          )
        }
        Spacer()
        Button(String(localized: "Cancel")) {
          dismiss()
        }
        Button(String(localized: "Add Selected")) {
          model.installPresets(
            GesturePresetLibrary.builtIn.filter {
              selectedIDs.contains($0.id)
            }
          )
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(selectedIDs.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 560, height: 520)
  }
}

struct GestureTemplatePreview: View {
  let template: GestureTemplate

  var body: some View {
    Canvas { context, size in
      guard
        let firstPoint = template.points.first,
        let first = point(firstPoint, in: size)
      else {
        return
      }
      var path = Path()
      path.move(to: first)
      for gesturePoint in template.points.dropFirst() {
        if let point = point(gesturePoint, in: size) {
          path.addLine(to: point)
        }
      }
      context.stroke(
        path,
        with: .color(.accentColor),
        style: StrokeStyle(
          lineWidth: 3,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }
    .background(
      .secondary.opacity(0.08),
      in: RoundedRectangle(
        cornerRadius: 6
      ))
  }

  private func point(
    _ point: GesturePoint,
    in size: CGSize
  ) -> CGPoint? {
    guard point.isFinite else { return nil }
    return CGPoint(
      x: (CGFloat(point.x) + 0.5) * size.width,
      y: (CGFloat(point.y) + 0.5) * size.height
    )
  }
}

struct AppScopeEditor: View {
  private enum Kind: String, CaseIterable, Identifiable {
    case all
    case only
    case allExcept

    var id: Self { self }

    var label: String {
      switch self {
      case .all:
        String(localized: "All Apps")
      case .only:
        String(localized: "Only These Apps")
      case .allExcept:
        String(localized: "All Except These Apps")
      }
    }
  }

  @Environment(\.dismiss) private var dismiss
  @State private var kind: Kind
  @State private var bundleIDs: [String]

  let onSave: (AppScope) -> Void

  init(
    scope: AppScope,
    onSave: @escaping (AppScope) -> Void
  ) {
    self.onSave = onSave
    switch scope {
    case .all:
      _kind = State(initialValue: .all)
      _bundleIDs = State(initialValue: [])
    case .only(let values):
      _kind = State(initialValue: .only)
      _bundleIDs = State(initialValue: values)
    case .allExcept(let values):
      _kind = State(initialValue: .allExcept)
      _bundleIDs = State(initialValue: values)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "Application Scope"))
        .font(.title2)

      Picker(String(localized: "Scope"), selection: $kind) {
        ForEach(Kind.allCases) { kind in
          Text(kind.label).tag(kind)
        }
      }
      .pickerStyle(.radioGroup)

      if kind != .all {
        HStack {
          Text(String(localized: "Applications"))
            .font(.headline)
          Spacer()
          Button(String(localized: "Choose Applications…")) {
            chooseApplications()
          }
        }

        if bundleIDs.isEmpty {
          ContentUnavailableView {
            Label(
              String(localized: "No Applications Selected"),
              systemImage: "app.dashed"
            )
          } description: {
            Text(
              String(
                localized:
                  "Select one or more applications for this scope."
              )
            )
          }
          .frame(height: 160)
        } else {
          List(bundleIDs.sorted(), id: \.self) { bundleID in
            applicationRow(bundleID: bundleID)
          }
          .frame(height: 180)
          .listStyle(.inset)
        }
      }

      HStack {
        Spacer()
        Button(String(localized: "Cancel")) {
          dismiss()
        }
        Button(String(localized: "Save")) {
          onSave(scope)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(kind != .all && bundleIDs.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 480)
  }

  private var scope: AppScope {
    let values = Array(Set(bundleIDs)).sorted()

    switch kind {
    case .all:
      return .all
    case .only:
      return .only(values)
    case .allExcept:
      return .allExcept(values)
    }
  }

  @ViewBuilder
  private func applicationRow(bundleID: String) -> some View {
    let applicationURL =
      NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleID
      )
    let name =
      applicationURL?.deletingPathExtension().lastPathComponent
      ?? bundleID

    HStack(spacing: 10) {
      if let applicationURL {
        Image(
          nsImage: NSWorkspace.shared.icon(
            forFile: applicationURL.path
          )
        )
        .resizable()
        .frame(width: 28, height: 28)
      } else {
        Image(systemName: "app.dashed")
          .frame(width: 28, height: 28)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
        Text(bundleID)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button(role: .destructive) {
        bundleIDs.removeAll { $0 == bundleID }
      } label: {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.borderless)
      .help(String(localized: "Remove Application"))
    }
  }

  private func chooseApplications() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = URL(
      fileURLWithPath: "/Applications",
      isDirectory: true
    )
    panel.prompt = String(localized: "Choose")
    panel.message = String(
      localized: "Choose applications for this gesture scope."
    )

    guard panel.runModal() == .OK else { return }
    let selectedBundleIDs = panel.urls.compactMap {
      Bundle(url: $0)?.bundleIdentifier
    }
    bundleIDs = Array(
      Set(bundleIDs + selectedBundleIDs)
    ).sorted()
  }
}

enum GestureActionSummary {
  static func text(for action: GestureAction) -> String {
    switch action {
    case .keyboardShortcut(let shortcut):
      return KeyboardShortcutFormatter.string(for: shortcut)
    case .openURL:
      return String(localized: "Open URL")
    case .launchApplication(let bundleIdentifier):
      return NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleIdentifier
      )?.deletingPathExtension().lastPathComponent
        ?? String(localized: "Open Application")
    case .system(let action):
      return systemActionName(action)
    case .appleShortcut(let name):
      return name.isEmpty
        ? String(localized: "Run Shortcut")
        : name
    case .sequence(let sequence):
      return String(
        format: String(localized: "Sequence · %d Steps"),
        sequence.steps.count
      )
    case .script(let script):
      return script.kind == .appleScript
        ? String(localized: "AppleScript")
        : String(localized: "Shell Script")
    }
  }

  static func systemActionName(
    _ action: SystemGestureAction
  ) -> String {
    switch action {
    case .missionControl:
      String(localized: "Mission Control")
    case .showDesktop:
      String(localized: "Show Desktop")
    case .lockScreen:
      String(localized: "Lock Screen")
    case .sleep:
      String(localized: "Sleep")
    case .volumeUp:
      String(localized: "Volume Up")
    case .volumeDown:
      String(localized: "Volume Down")
    case .mute:
      String(localized: "Mute")
    case .brightnessUp:
      String(localized: "Brightness Up")
    case .brightnessDown:
      String(localized: "Brightness Down")
    case .appSwitcher:
      String(localized: "Application Switcher")
    }
  }
}

struct GestureActionEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var action: GestureAction

  let model: AppModel
  let onSave: (GestureAction) -> Void

  init(
    action: GestureAction,
    model: AppModel,
    onSave: @escaping (GestureAction) -> Void
  ) {
    _action = State(initialValue: action)
    self.model = model
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(String(localized: "Action"))
        .font(.title2)
      GestureActionEditor(action: $action, model: model)
      HStack {
        Spacer()
        Button(String(localized: "Cancel")) {
          dismiss()
        }
        Button(String(localized: "Save")) {
          onSave(action)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!action.isValid)
      }
    }
    .padding(24)
    .frame(width: 520)
  }
}

struct GestureActionEditor: View {
  private enum Kind: String, CaseIterable, Identifiable {
    case keyboardShortcut
    case openURL
    case launchApplication
    case system
    case appleShortcut
    case sequence
    case script

    var id: Self { self }

    var label: String {
      switch self {
      case .keyboardShortcut:
        String(localized: "Keyboard Shortcut")
      case .openURL:
        String(localized: "Open URL")
      case .launchApplication:
        String(localized: "Open Application")
      case .system:
        String(localized: "System Action")
      case .appleShortcut:
        String(localized: "Run Apple Shortcut")
      case .sequence:
        String(localized: "Action Sequence")
      case .script:
        String(localized: "Script")
      }
    }
  }

  @Binding var action: GestureAction
  let model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker(String(localized: "Action Type"), selection: kind) {
        ForEach(Kind.allCases) { kind in
          Text(kind.label).tag(kind)
        }
      }

      switch action {
      case .keyboardShortcut:
        ShortcutRecorderView(
          shortcut: keyboardShortcut,
          model: model
        )
        .frame(width: 180)
      case .openURL:
        TextField(
          String(localized: "https://example.com"),
          text: stringValue(
            extract: {
              guard case .openURL(let value) = $0 else { return "" }
              return value
            },
            embed: GestureAction.openURL
          )
        )
      case .launchApplication(let bundleIdentifier):
        HStack {
          Text(
            GestureActionSummary.text(
              for: .launchApplication(
                bundleIdentifier: bundleIdentifier
              )
            )
          )
          Spacer()
          Button(String(localized: "Choose Application…")) {
            chooseApplication()
          }
        }
      case .system:
        Picker(
          String(localized: "System Action"),
          selection: systemAction
        ) {
          ForEach(SystemGestureAction.allCases, id: \.self) {
            Text(GestureActionSummary.systemActionName($0)).tag($0)
          }
        }
      case .appleShortcut:
        TextField(
          String(localized: "Shortcut Name"),
          text: stringValue(
            extract: {
              guard case .appleShortcut(let name) = $0 else {
                return ""
              }
              return name
            },
            embed: { .appleShortcut(name: $0) }
          )
        )
      case .sequence:
        SequenceActionEditor(sequence: sequence, model: model)
      case .script:
        ScriptActionEditor(script: script)
      }
    }
  }

  private var kind: Binding<Kind> {
    Binding(
      get: {
        switch action {
        case .keyboardShortcut:
          .keyboardShortcut
        case .openURL:
          .openURL
        case .launchApplication:
          .launchApplication
        case .system:
          .system
        case .appleShortcut:
          .appleShortcut
        case .sequence:
          .sequence
        case .script:
          .script
        }
      },
      set: {
        switch $0 {
        case .keyboardShortcut:
          action = .keyboardShortcut(
            ShortcutRecordingSession.emptyShortcut
          )
        case .openURL:
          action = .openURL("https://")
        case .launchApplication:
          action = .launchApplication(bundleIdentifier: "")
        case .system:
          action = .system(.missionControl)
        case .appleShortcut:
          action = .appleShortcut(name: "")
        case .sequence:
          action = .sequence(
            GestureActionSequence(
              steps: [
                GestureActionStep(action: .system(.missionControl))
              ]
            )
          )
        case .script:
          action = .script(
            AutomationScript(
              kind: .appleScript,
              source: ""
            )
          )
        }
      }
    )
  }

  private var keyboardShortcut: Binding<KeyboardShortcut> {
    Binding(
      get: {
        action.keyboardShortcut
          ?? ShortcutRecordingSession.emptyShortcut
      },
      set: { action = .keyboardShortcut($0) }
    )
  }

  private var systemAction: Binding<SystemGestureAction> {
    Binding(
      get: {
        guard case .system(let value) = action else {
          return .missionControl
        }
        return value
      },
      set: { action = .system($0) }
    )
  }

  private var sequence: Binding<GestureActionSequence> {
    Binding(
      get: {
        guard case .sequence(let value) = action else {
          return GestureActionSequence(steps: [])
        }
        return value
      },
      set: { action = .sequence($0) }
    )
  }

  private var script: Binding<AutomationScript> {
    Binding(
      get: {
        guard case .script(let value) = action else {
          return AutomationScript(kind: .appleScript, source: "")
        }
        return value
      },
      set: { action = .script($0) }
    )
  }

  private func stringValue(
    extract: @escaping (GestureAction) -> String,
    embed: @escaping (String) -> GestureAction
  ) -> Binding<String> {
    Binding(
      get: { extract(action) },
      set: { action = embed($0) }
    )
  }

  private func chooseApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = URL(
      fileURLWithPath: "/Applications",
      isDirectory: true
    )
    panel.prompt = String(localized: "Choose")
    guard panel.runModal() == .OK,
      let url = panel.url,
      let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
    else {
      return
    }
    action = .launchApplication(
      bundleIdentifier: bundleIdentifier
    )
  }
}

private struct SequenceActionEditor: View {
  @Binding var sequence: GestureActionSequence
  let model: AppModel
  @State private var editingStepIndex: Int?
  @State private var isEditingFallback = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(sequence.steps.indices, id: \.self) { index in
        HStack {
          Text("\(index + 1).")
          Button(
            GestureActionSummary.text(
              for: sequence.steps[index].action
            )
          ) {
            editingStepIndex = index
          }
          Stepper(
            value: $sequence.steps[index].delayAfter,
            in: 0...5,
            step: 0.25
          ) {
            Text(
              String(
                format: String(localized: "%.2f s delay"),
                sequence.steps[index].delayAfter
              )
            )
          }
          Button(role: .destructive) {
            sequence.steps.remove(at: index)
          } label: {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.borderless)
        }
      }

      HStack {
        Button(String(localized: "Add Step")) {
          guard sequence.steps.count < 20 else { return }
          sequence.steps.append(
            GestureActionStep(action: .system(.missionControl))
          )
        }

        Picker(
          String(localized: "On Failure"),
          selection: failureKind
        ) {
          Text(String(localized: "Stop")).tag(0)
          Text(String(localized: "Continue")).tag(1)
          Text(String(localized: "Run Fallback")).tag(2)
        }

        if case .fallback(let action) = sequence.failurePolicy {
          Button(GestureActionSummary.text(for: action)) {
            isEditingFallback = true
          }
        }
      }
    }
    .sheet(
      isPresented: Binding(
        get: { editingStepIndex != nil },
        set: {
          if !$0 {
            editingStepIndex = nil
          }
        }
      )
    ) {
      if let index = editingStepIndex,
        sequence.steps.indices.contains(index)
      {
        GestureActionEditorSheet(
          action: sequence.steps[index].action,
          model: model
        ) {
          sequence.steps[index].action = $0
        }
      }
    }
    .sheet(isPresented: $isEditingFallback) {
      if case .fallback(let action) = sequence.failurePolicy {
        GestureActionEditorSheet(action: action, model: model) {
          sequence.failurePolicy = .fallback($0)
        }
      }
    }
  }

  private var failureKind: Binding<Int> {
    Binding(
      get: {
        switch sequence.failurePolicy {
        case .stop:
          0
        case .continue:
          1
        case .fallback:
          2
        }
      },
      set: {
        switch $0 {
        case 1:
          sequence.failurePolicy = .continue
        case 2:
          sequence.failurePolicy = .fallback(
            .system(.showDesktop)
          )
        default:
          sequence.failurePolicy = .stop
        }
      }
    )
  }
}

private struct ScriptActionEditor: View {
  @Binding var script: AutomationScript

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker(String(localized: "Script Type"), selection: $script.kind) {
        Text(String(localized: "AppleScript"))
          .tag(AutomationScriptKind.appleScript)
        Text(String(localized: "Shell"))
          .tag(AutomationScriptKind.shell)
      }

      TextEditor(text: $script.source)
        .font(.system(.body, design: .monospaced))
        .frame(height: 120)
        .border(.secondary.opacity(0.3))

      Stepper(
        value: $script.timeout,
        in: 1...30,
        step: 1
      ) {
        Text(
          String(
            format: String(localized: "Timeout: %.0f seconds"),
            script.timeout
          )
        )
      }

      Toggle(
        String(
          localized:
            "I created or reviewed this script and understand it can control this Mac."
        ),
        isOn: $script.isConfirmed
      )
      .foregroundStyle(
        script.isConfirmed ? Color.primary : Color.orange
      )
    }
  }
}
