import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GesturesSettingsView: View {
  @ObservedObject var model: AppModel
  @State private var isPresentingRecorder = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(String(localized: "Gestures"))
          .font(.title2)
          .fontWeight(.semibold)
        Spacer()
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
                "Record a gesture and bind it to a keyboard shortcut."
            )
          )
        } actions: {
          Button(String(localized: "Record Gesture")) {
            isPresentingRecorder = true
          }
        }
      } else {
        List {
          ForEach(
            Array(model.mappings.enumerated()),
            id: \.element.id
          ) { index, mapping in
            GestureMappingRow(
              model: model,
              mapping: mapping,
              index: index,
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
  }
}

private struct GestureMappingRow: View {
  @ObservedObject var model: AppModel
  let mapping: GestureMapping
  let index: Int
  let mappingCount: Int

  @State private var name: String
  @State private var isEditingScope = false
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
    HStack(spacing: 12) {
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
        .frame(minWidth: 120)
        .onSubmit {
          commitName()
        }
        .onChange(of: mapping.name) { _, newValue in
          name = newValue
        }

      ShortcutRecorderView(
        shortcut: Binding(
          get: { mapping.shortcut },
          set: {
            model.setMappingShortcut(
              id: mapping.id,
              shortcut: $0
            )
          }
        ),
        model: model
      )
      .frame(width: 120)

      if let conflict = shortcutConflict {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .help(conflict.localizedDescription)
      }

      Button(scopeSummary) {
        isEditingScope = true
      }
      .frame(width: 140)

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

        Button(role: .destructive) {
          isConfirmingDeletion = true
        } label: {
          Image(systemName: "trash")
        }
        .help(String(localized: "Delete Gesture"))
      }
      .buttonStyle(.borderless)
    }
    .padding(.vertical, 4)
    .sheet(isPresented: $isEditingScope) {
      AppScopeEditor(scope: mapping.appScope) {
        model.setMappingAppScope(id: mapping.id, appScope: $0)
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
    SystemShortcutConflictDetector().conflict(
      for: mapping.shortcut
    )
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
}

private struct AppScopeEditor: View {
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
